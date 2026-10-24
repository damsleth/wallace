import sys,hashlib,json,pathlib,struct
sys.path.insert(0,'/Users/damsleth/Code/m1n1/proxyclient')
from m1n1.adt import load_adt
def walk(n):
 yield n
 for c in n:
  yield from walk(c)
out={}
for name in ['j614s-full-20260728.adt','j614s-usb-port-map-20260721.adt']:
 p=pathlib.Path('/Users/damsleth/Code/linux-build-out')/name;b=p.read_bytes();a=load_adt(b)
 d={'path':str(p),'sha256':hashlib.sha256(b).hexdigest(),'nodes':{}}
 for n in walk(a):
  if n._parent is None:continue
  if any(x in n._path for x in ['apcie0/pci-bridge','amfm']) or n._path.replace('/device-tree','') in ['/arm-io/ans','/arm-io/sart-ans','/arm-io/mtp','/arm-io/gpio0','/arm-io/smc','/arm-io/dart-mtp','/arm-io/dockchannel-mtp','/arm-io/dockchannel-uart','/arm-io/apcie0'] or ('/arm-io/' in n._path and any(x in n.name for x in ['dispext','disp0','dcpext','dockchannel'])):
   v={}
   for k in ['compatible','interrupts','no-restore-gpio-pins','sart-version','sart-power-reg-offset','sart-power-managed','power-gates','clock-gates','nvme-interrupt-idx','nvme-queue-entries','#gpio-pins','ranges','port-index','function-clkreq','function-sd_pwr_en','function-perst','function-reg_on','wifi-antenna-sku-info','module-instance']:
    if k in n._properties:
     raw=n._properties[k]
     if isinstance(raw,bytes):v[k]={'hex':raw.hex(),'u32le':list(struct.unpack('<'+'I'*(len(raw)//4),raw))} if len(raw)%4==0 else raw.hex()
     else:v[k]=str(raw)
   if isinstance(getattr(n,'reg',None),list):
    v['reg']=[{'index':i,'raw':hex(r.addr),'cpu':hex(n.get_reg(i)[0]),'size':hex(r.size)} for i,r in enumerate(n.reg) if hasattr(r,'addr') and isinstance(r.addr,int)]
   d['nodes'][n._path]=v
 pm=a['/arm-io/pmgr']
 d['display_domains']=[{'name':x.name,'id':x.id2,'parents':str(x.parents_un),'offset':hex(x.offset)} for x in pm.devices if any(s in x.name for s in ['DISP','ANS'])]
 out[name]=d
p=pathlib.Path('.tmp/convergence-6002/adt-summary.json');p.write_text(json.dumps(out,indent=2)+'\n');print(p)
print('domains',len(out['j614s-full-20260728.adt']['display_domains']))
print('\n'.join(out['j614s-full-20260728.adt']['nodes']))
