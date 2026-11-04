"""Read actual Gowin P&R STA (not synthesis estimates); fail on negative slack."""
from pathlib import Path
import argparse, json, re
from bs4 import BeautifulSoup
ap=argparse.ArgumentParser()
ap.add_argument('--input',default='impl/pnr/ui10_spectrum32_tr_content.html')
ap.add_argument('--output',default='results/final/timing_audit')
ap.add_argument('--require-pass',action='store_true')
a=ap.parse_args()
source=Path(a.input); soup=BeautifulSoup(source.read_text(encoding='utf-8'),'html.parser')
text=soup.get_text(' ',strip=True).replace('&nbsp',' ')
def rows(table):
    return [[c.get_text(' ',strip=True) for c in r.find_all(['td','th'])] for r in table.find_all('tr')]
def section(name):
    anchor=soup.find('a',attrs={'name':name})
    return rows(anchor.find_next('table')) if anchor else []
setup=section('Setup_Slack_Table'); hold=section('Hold_Slack_Table')
def paths(records):
    return [dict(rank=int(r[0]),slack=float(r[1]),start=r[2],end=r[3],
                 source_clock=r[4],destination_clock=r[5],module='/'.join(r[3].split('/')[:-2]))
            for r in records if len(r)>=6 and r[0].isdigit()]
details={}
in_setup=False
for h in soup.find_all(['h2','h3']):
    title=h.get_text(' ',strip=True)
    if title=='Setup Analysis Report': in_setup=True
    elif title=='Hold Analysis Report': in_setup=False
    m=re.fullmatch(r'Path\s*(\d+)',title)
    if not in_setup or not m: continue
    parts=[]
    for x in h.next_siblings:
        if getattr(x,'name',None) in ['h2','h3']: break
        if hasattr(x,'get_text'): parts.append(x.get_text(' ',strip=True))
    s=' '.join(parts)
    level=re.search(r'Logic Level\s*:?\s*(\d+)',s)
    details.setdefault(int(m[1]),int(level[1]) if level else None)
ps=paths(setup)
for p in ps:p['levels']=details.get(p['rank'])
summary=section('STA_Tool_Run_Summary')
violations={key:int(val) for key,val in re.findall(r'(Numbers of (?:Setup|Hold) Violated Endpoints)\s+(\d+)',text)}
result={'source':str(source.resolve()),'violations':violations,'setup':ps,'hold':paths(hold),
        'recovery':paths(section('Recovery_Slack_Table')),'removal':paths(section('Removal_Slack_Table')),
        'clocks':section('Clock_Report'),'max_frequency':section('Max_Frequency_Report')}
out=Path(a.output);out.parent.mkdir(parents=True,exist_ok=True)
out.with_suffix('.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
lines=['# Gowin P&R 时序审计','',f'来源：{source.resolve()}','',str(violations),'',
       '|序号|Slack/ns|起点|终点|所属模块|逻辑级数|','|---:|---:|---|---|---|---:|']
for p in ps[:20]:lines.append(f"|{p['rank']}|{p['slack']}|{p['start']}|{p['end']}|{p['module']}|{p['levels']}|")
lines+=['','## 时钟表','',*[' | '.join(r) for r in result['clocks']],
        '','## 最高频率','',*[' | '.join(r) for r in result['max_frequency']]]
out.with_suffix('.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
bad=not ps or any(p['slack']<0 for p in ps+result['hold']+result['recovery']+result['removal']) or any(violations.values())
print(('FAIL' if bad else 'PASS'),violations,'worst setup',min((p['slack'] for p in ps),default=None),
      'worst hold',min((p['slack'] for p in result['hold']),default=None),'->',out.with_suffix('.md'))
if a.require_pass and bad:raise SystemExit(1)
