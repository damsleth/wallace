/*
 * Bridge the Linux T6040 diagnostic gadget's first CDC-ACM data interface to
 * a host pseudo-terminal using libusb.
 *
 * This deliberately refuses m1n1's own 1209:316d proxy gadget by requiring
 * the exact Linux diagnostic product string before claiming an interface.
 * It is a host-side fallback for macOS systems where the USB device reaches
 * SetConfiguration but the CDC class driver publishes no /dev/cu.usbmodem*.
 */

#include <errno.h>
#include <getopt.h>
#include <libusb.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>
#include <util.h>

#define DEFAULT_VID 0x1209
#define DEFAULT_PID 0x316d
#define EXPECTED_PRODUCT "m1n1-shaped Linux ACM diagnostic"
#define USB_TIMEOUT_MS 1000
#define BUFFER_SIZE 16384

struct bridge {
	libusb_device_handle *handle;
	int pty_master;
	unsigned char ep_in;
	unsigned char ep_out;
	volatile sig_atomic_t stop;
	volatile sig_atomic_t failed;
};

static struct bridge *signal_bridge;

static void stop_bridge(int signo)
{
	(void)signo;
	if (signal_bridge)
		signal_bridge->stop = 1;
}

static int write_all(int fd, const unsigned char *buf, size_t len)
{
	while (len) {
		ssize_t written = write(fd, buf, len);

		if (written > 0) {
			buf += written;
			len -= (size_t)written;
			continue;
		}
		if (written < 0 && errno == EINTR)
			continue;
		return -1;
	}

	return 0;
}

static void *usb_to_pty(void *opaque)
{
	struct bridge *bridge = opaque;
	unsigned char buf[BUFFER_SIZE];

	while (!bridge->stop) {
		int transferred = 0;
		int ret = libusb_bulk_transfer(bridge->handle, bridge->ep_in, buf,
					      sizeof(buf), &transferred,
					      USB_TIMEOUT_MS);

		if (ret == LIBUSB_ERROR_TIMEOUT)
			continue;
		if (ret != LIBUSB_SUCCESS) {
			fprintf(stderr, "USB IN failed: %s\n",
				libusb_error_name(ret));
			bridge->failed = 1;
			bridge->stop = 1;
			break;
		}
		if (transferred && write_all(bridge->pty_master, buf,
					    (size_t)transferred)) {
			perror("write PTY");
			bridge->failed = 1;
			bridge->stop = 1;
			break;
		}
	}

	return NULL;
}

static libusb_device_handle *open_diagnostic(uint16_t vid, uint16_t pid)
{
	libusb_device **devices = NULL;
	libusb_device_handle *match = NULL;
	ssize_t count = libusb_get_device_list(NULL, &devices);

	if (count < 0) {
		fprintf(stderr, "libusb_get_device_list: %s\n",
			libusb_error_name((int)count));
		return NULL;
	}

	for (ssize_t i = 0; i < count; i++) {
		struct libusb_device_descriptor desc;
		libusb_device_handle *handle = NULL;
		unsigned char product[256] = {0};

		if (libusb_get_device_descriptor(devices[i], &desc) ||
		    desc.idVendor != vid || desc.idProduct != pid)
			continue;
		if (libusb_open(devices[i], &handle) != LIBUSB_SUCCESS)
			continue;
		if (!desc.iProduct ||
		    libusb_get_string_descriptor_ascii(handle, desc.iProduct,
						       product,
						       sizeof(product)) < 0 ||
		    strcmp((char *)product, EXPECTED_PRODUCT)) {
			fprintf(stderr,
				"refusing %04x:%04x product '%s' (expected '%s')\n",
				vid, pid, product[0] ? (char *)product : "<unreadable>",
				EXPECTED_PRODUCT);
			libusb_close(handle);
			continue;
		}
		match = handle;
		break;
	}

	libusb_free_device_list(devices, 1);
	return match;
}

static int find_acm_data_interface(libusb_device_handle *handle,
				   unsigned int function_index,
				   int *control_interface,
				   int *data_interface,
				   unsigned char *ep_in,
				   unsigned char *ep_out)
{
	struct libusb_config_descriptor *config = NULL;
	libusb_device *device = libusb_get_device(handle);
	unsigned int found = 0;
	int ret = libusb_get_active_config_descriptor(device, &config);

	if (ret != LIBUSB_SUCCESS)
		return ret;

	ret = LIBUSB_ERROR_NOT_FOUND;
	for (uint8_t i = 0; i < config->bNumInterfaces; i++) {
		const struct libusb_interface *interface = &config->interface[i];

		for (int a = 0; a < interface->num_altsetting; a++) {
			const struct libusb_interface_descriptor *alt =
				&interface->altsetting[a];
			unsigned char in = 0, out = 0;

			if (alt->bAlternateSetting ||
			    alt->bInterfaceClass != LIBUSB_CLASS_DATA)
				continue;
			if (found++ != function_index)
				continue;

			for (uint8_t e = 0; e < alt->bNumEndpoints; e++) {
				const struct libusb_endpoint_descriptor *ep =
					&alt->endpoint[e];

				if ((ep->bmAttributes &
				     LIBUSB_TRANSFER_TYPE_MASK) !=
				    LIBUSB_TRANSFER_TYPE_BULK)
					continue;
				if (ep->bEndpointAddress & LIBUSB_ENDPOINT_IN)
					in = ep->bEndpointAddress;
				else
					out = ep->bEndpointAddress;
			}
			if (!in || !out)
				break;

			*data_interface = alt->bInterfaceNumber;
			/*
			 * Linux f_acm allocates each control interface
			 * immediately before its paired data interface.
			 */
			*control_interface = alt->bInterfaceNumber - 1;
			*ep_in = in;
			*ep_out = out;
			ret = LIBUSB_SUCCESS;
			goto out;
		}
	}

out:
	libusb_free_config_descriptor(config);
	return ret;
}

static int configure_acm(libusb_device_handle *handle, int control_interface)
{
	/* 115200 8N1, matching m1n1's harmless default line coding. */
	unsigned char line_coding[7] = {
		0x00, 0xc2, 0x01, 0x00, 0x00, 0x00, 0x08
	};
	int ret;

	ret = libusb_control_transfer(handle,
				      LIBUSB_ENDPOINT_OUT |
				      LIBUSB_REQUEST_TYPE_CLASS |
				      LIBUSB_RECIPIENT_INTERFACE,
				      0x20, 0, (uint16_t)control_interface,
				      line_coding, sizeof(line_coding),
				      USB_TIMEOUT_MS);
	if (ret != (int)sizeof(line_coding))
		return ret < 0 ? ret : LIBUSB_ERROR_IO;

	ret = libusb_control_transfer(handle,
				      LIBUSB_ENDPOINT_OUT |
				      LIBUSB_REQUEST_TYPE_CLASS |
				      LIBUSB_RECIPIENT_INTERFACE,
				      0x22, 3, (uint16_t)control_interface,
				      NULL, 0, USB_TIMEOUT_MS);
	return ret < 0 ? ret : LIBUSB_SUCCESS;
}

static void usage(const char *program)
{
	fprintf(stderr,
		"usage: %s [--function N] [--vid HEX] [--pid HEX]\n",
		program);
}

int main(int argc, char **argv)
{
	uint16_t vid = DEFAULT_VID, pid = DEFAULT_PID;
	unsigned int function_index = 0;
	int control_interface = -1, data_interface = -1;
	int pty_master = -1, pty_slave = -1;
	char pty_name[128] = {0};
	struct termios termios;
	struct bridge bridge = {0};
	pthread_t reader;
	bool reader_started = false;
	int ret;
	int exit_status = EXIT_FAILURE;
	static const struct option options[] = {
		{"function", required_argument, NULL, 'f'},
		{"vid", required_argument, NULL, 'v'},
		{"pid", required_argument, NULL, 'p'},
		{"help", no_argument, NULL, 'h'},
		{NULL, 0, NULL, 0},
	};

	for (;;) {
		char *end = NULL;
		unsigned long value;
		int opt = getopt_long(argc, argv, "f:v:p:h", options, NULL);

		if (opt == -1)
			break;
		if (opt == 'h') {
			usage(argv[0]);
			return EXIT_SUCCESS;
		}
		if (opt != 'f' && opt != 'v' && opt != 'p') {
			usage(argv[0]);
			return EXIT_FAILURE;
		}
		errno = 0;
		value = strtoul(optarg, &end, 0);
		if (errno || !end || *end ||
		    (opt == 'f' && value > 255) ||
		    (opt != 'f' && value > UINT16_MAX)) {
			usage(argv[0]);
			return EXIT_FAILURE;
		}
		if (opt == 'f')
			function_index = (unsigned int)value;
		else if (opt == 'v')
			vid = (uint16_t)value;
		else
			pid = (uint16_t)value;
	}
	if (optind != argc) {
		usage(argv[0]);
		return EXIT_FAILURE;
	}

	ret = libusb_init(NULL);
	if (ret != LIBUSB_SUCCESS) {
		fprintf(stderr, "libusb_init: %s\n", libusb_error_name(ret));
		return EXIT_FAILURE;
	}

	bridge.handle = open_diagnostic(vid, pid);
	if (!bridge.handle) {
		fprintf(stderr, "Linux diagnostic gadget %04x:%04x not found\n",
			vid, pid);
		goto out_usb;
	}

	ret = find_acm_data_interface(bridge.handle, function_index,
				      &control_interface, &data_interface,
				      &bridge.ep_in, &bridge.ep_out);
	if (ret != LIBUSB_SUCCESS) {
		fprintf(stderr, "ACM data function %u not found: %s\n",
			function_index, libusb_error_name(ret));
		goto out_handle;
	}

	libusb_set_auto_detach_kernel_driver(bridge.handle, 1);
	ret = libusb_claim_interface(bridge.handle, control_interface);
	if (ret != LIBUSB_SUCCESS) {
		fprintf(stderr, "claim control interface %d: %s\n",
			control_interface, libusb_error_name(ret));
		goto out_handle;
	}
	ret = libusb_claim_interface(bridge.handle, data_interface);
	if (ret != LIBUSB_SUCCESS) {
		fprintf(stderr, "claim data interface %d: %s\n",
			data_interface, libusb_error_name(ret));
		goto out_control;
	}

	ret = configure_acm(bridge.handle, control_interface);
	if (ret != LIBUSB_SUCCESS) {
		fprintf(stderr, "configure ACM: %s\n", libusb_error_name(ret));
		goto out_data;
	}

	if (openpty(&pty_master, &pty_slave, pty_name, NULL, NULL)) {
		perror("openpty");
		goto out_dtr;
	}
	if (tcgetattr(pty_slave, &termios)) {
		perror("tcgetattr PTY");
		goto out_pty;
	}
	cfmakeraw(&termios);
	cfsetispeed(&termios, B115200);
	cfsetospeed(&termios, B115200);
	if (tcsetattr(pty_slave, TCSANOW, &termios)) {
		perror("tcsetattr PTY");
		goto out_pty;
	}
	bridge.pty_master = pty_master;
	signal_bridge = &bridge;
	signal(SIGINT, stop_bridge);
	signal(SIGTERM, stop_bridge);

	if (pthread_create(&reader, NULL, usb_to_pty, &bridge)) {
		perror("pthread_create");
		goto out_pty;
	}
	reader_started = true;

	printf("%s\n", pty_name);
	fprintf(stderr,
		"bridging function %u: control=%d data=%d IN=0x%02x OUT=0x%02x\n",
		function_index, control_interface, data_interface,
		bridge.ep_in, bridge.ep_out);
	fflush(stdout);

	while (!bridge.stop) {
		struct pollfd pollfd = {
			.fd = pty_master,
			.events = POLLIN,
		};
		unsigned char buf[BUFFER_SIZE];
		ssize_t length;
		int transferred = 0;

		ret = poll(&pollfd, 1, USB_TIMEOUT_MS);
		if (ret < 0) {
			if (errno == EINTR)
				continue;
			perror("poll PTY");
			bridge.failed = 1;
			break;
		}
		if (!ret || !(pollfd.revents & POLLIN))
			continue;

		length = read(pty_master, buf, sizeof(buf));
		if (length < 0) {
			if (errno == EINTR || errno == EIO)
				continue;
			perror("read PTY");
			bridge.failed = 1;
			break;
		}
		if (!length)
			continue;

		ret = libusb_bulk_transfer(bridge.handle, bridge.ep_out, buf,
					   (int)length, &transferred,
					   USB_TIMEOUT_MS);
		if (ret != LIBUSB_SUCCESS || transferred != length) {
			fprintf(stderr, "USB OUT failed: %s (%d/%zd)\n",
				libusb_error_name(ret), transferred, length);
			bridge.failed = 1;
			break;
		}
	}

	exit_status = bridge.failed ? EXIT_FAILURE : EXIT_SUCCESS;
	bridge.stop = 1;
	if (reader_started)
		pthread_join(reader, NULL);
out_pty:
	close(pty_slave);
	close(pty_master);
out_dtr:
	libusb_control_transfer(bridge.handle,
				LIBUSB_ENDPOINT_OUT |
				LIBUSB_REQUEST_TYPE_CLASS |
				LIBUSB_RECIPIENT_INTERFACE,
				0x22, 0, (uint16_t)control_interface,
				NULL, 0, USB_TIMEOUT_MS);
out_data:
	libusb_release_interface(bridge.handle, data_interface);
out_control:
	libusb_release_interface(bridge.handle, control_interface);
out_handle:
	libusb_close(bridge.handle);
out_usb:
	libusb_exit(NULL);
	return exit_status;
}
