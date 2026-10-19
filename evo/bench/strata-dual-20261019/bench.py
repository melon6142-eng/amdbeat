import json,time,urllib.request,concurrent.futures as cf,random
import sys;U=sys.argv[1];M=sys.argv[2]
def run(prompt,mx=512):
    body=json.dumps({"model":M,"messages":[{"role":"user","content":prompt}],"max_tokens":mx,"stream":True,"temperature":0.6,"stream_options":{"include_usage":True}}).encode()
    r=urllib.request.Request(U,body,{"Content-Type":"application/json"});t0=time.time();tf=None;n=0;usage=None
    with urllib.request.urlopen(r,timeout=900) as f:
        for l in f:
            l=l.decode().strip()
            if not l.startswith("data:") or l=="data: [DONE]":continue
            d=json.loads(l[5:])
            if d.get("usage"):usage=d["usage"]
            for c in d.get("choices",[]):
                dl=c.get("delta",{})
                if dl.get("content") or dl.get("reasoning_content") or dl.get("reasoning"):
                    if tf is None:tf=time.time()
                    n+=1
    t1=time.time();ct=(usage or {}).get("completion_tokens",n);pt=(usage or {}).get("prompt_tokens")
    return dict(ttft=round(tf-t0,2),dec=round((ct-1)/(t1-tf),1),ct=ct,pt=pt)
code="Write a complete Python module that parses MLCC dielectric layer thickness measurements from CSV, computes statistics per lot, flags outliers with IQR, and plots histograms. Include docstrings and tests."
prose="Write a long, detailed essay about the history of ceramic capacitors and how multilayer manufacturing evolved."
print("code1",run(code),flush=True);print("prose1",run(prose),flush=True)
for k in (4,16,32):
    words=" ".join(random.choice(["slurry","binder","viscosity","sheet","electrode","nickel","sinter","BaTiO3","layer","defect","crack","delam"]) for _ in range(int(k*1000*0.75)))
    print("prefill%dk"%k,(lambda r:dict(r,pf=round(r["pt"]/r["ttft"]) if r["pt"] else None))(run("Summarize in one sentence: "+words,mx=16)),flush=True)
for c in (2,4,8):
    t0=time.time()
    with cf.ThreadPoolExecutor(c) as ex: rs=list(ex.map(lambda _:run(code,384),range(c)))
    w=time.time()-t0
    print("conc%d"%c,"per",[r["dec"] for r in rs],"agg",round(sum(r["ct"] for r in rs)/w,1),"ttft",[r["ttft"] for r in rs],flush=True)
