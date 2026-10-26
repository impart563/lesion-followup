import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve,join } from "node:path";
import { pathToFileURL } from "node:url";
const folder=resolve(process.argv[2]),load=name=>import(pathToFileURL(join(folder,name)));
const {evaluate}=await load('browser.js');
const {invoke,serializeTable}=await load('workbench.mjs');
const {prepareVisitEdit,createVisitPlanner}=await load('visit-editor.mjs');
const {observationForm,describeObservation}=await load('observation-editor.mjs');
const source={study_json:readFileSync('examples/study.json','utf8').replace(/\n/g,'\r\n'),followup_csv:readFileSync('examples/followup.csv','utf8')};
const model=s=>invoke(evaluate,{action:'editor',...s}).result;
const measurements=(id,state,diameter_mm='',note='')=>({lesion_id:id,state,diameter_mm,note});
const operation=(visit_id,values)=>({kind:'observations',visit_id,measurements:values});
const native=[];
function collect(name,sources){
 const outputs=Object.fromEntries(['json','csv','html','markdown','svg'].map(format=>{
  const result=invoke(evaluate,{action:'review',...sources,format,language:'zh-CN'});assert.equal(result.ok,true);return[format,result.result.content];
 }));
 native.push({name,source:sources,preflight:invoke(evaluate,{action:'preflight',...sources}).preflight,outputs});
}
const added=prepareVisitEdit(evaluate,source,{kind:'append',id:'week-10',date:'2026-03-15',technique_id:'ct-venous-5mm'}).sources;
const input=operation('week-10',[measurements('N1','measured','10.0'),measurements('T1','measured','18.0')]);
const completed=prepareVisitEdit(evaluate,added,input);
assert.equal(completed.sources.study_json,source.study_json);assert.equal(completed.summary.changes.length,2);
assert.deepEqual(model(completed.sources).rows.slice(0,8),model(source).rows);
assert.deepEqual(model(completed.sources).rows.slice(8).map(row=>row.slice(3)),[['T1','measured','18.0',''],['N1','measured','10.0','']]);
collect('completed-missing-visit',completed.sources);
const reason='<script>合成说明</script>, "不可评价"\r\n第二行 Ω 😀';
const unavailable=prepareVisitEdit(evaluate,source,operation('week-2',[measurements('T1','not_evaluable','',reason),measurements('N1','too_small')]));
assert.equal(model(unavailable.sources).rows[0][6],reason);assert.equal(unavailable.summary.changes[0].before.diameter_mm,'20.0');
assert.ok(describeObservation(unavailable.summary.changes[0].after).includes(reason));
collect('state-replacement-and-reason',unavailable.sources);
const five={study:structuredClone(model(source).study),rows:[]};
five.study.targets=Array.from({length:5},(_,i)=>({id:'T'+(i+1),organ:'organ-'+(i+1),kind:'non_nodal',baseline_mm:'30.0'}));
const fiveSource=prepareVisitEdit(evaluate,serializeTable(five),{kind:'append',id:'v1',date:'2026-01-02',technique_id:'ct-venous-5mm'}).sources;
const allStates=prepareVisitEdit(evaluate,fiveSource,operation('v1',[measurements('T1','measured','20.0'),measurements('T2','absent'),measurements('T3','too_small'),measurements('T4','missing'),measurements('T5','not_evaluable','',reason)]));
collect('five-supported-states',allStates.sources);
const omitted=model(source);omitted.rows.splice(1,1);const omittedSource=serializeTable(omitted);
const form=observationForm(model(omittedSource),'week-2');assert.equal(form[1].state,'missing');
form[0].state='changed';assert.equal(model(omittedSource).rows[0][4],'measured');
const filled=prepareVisitEdit(evaluate,omittedSource,operation('week-2',[measurements('T1','measured','20.0'),measurements('N1','measured','15.0')]));
assert.equal(filled.summary.changes[0].before,null);assert.equal(model(filled.sources).rows.length,8);
collect('fill-omitted-target',filled.sources);
assert.equal(prepareVisitEdit(evaluate,completed.sources,input).summary.changes.length,0);
const original=structuredClone(source),bad=[];
for(const update of [{measurements:null},{measurements:[]},{extra:true},{visit_id:'absent'},{visit_id:4}])bad.push({...input,...update});
for(const update of [{state:'unknown'},{state:'measured',diameter_mm:'18.01'},{state:'measured',diameter_mm:'-1'},
 {state:'measured',diameter_mm:'1000.1'},{state:'measured',diameter_mm:''},{state:'measured',note:'unexpected'},
 {state:'not_evaluable',diameter_mm:'',note:''},{state:'absent',diameter_mm:'1.0'},{state:'missing',diameter_mm:'0'},
 {state:'too_small',note:'unexpected'},{lesion_id:'unknown'},{extra:true},{diameter_mm:18}]){
 const changed=structuredClone(input);Object.assign(changed.measurements[1],update);bad.push(changed);
}
bad.push(operation('week-10',[measurements('T1','missing'),measurements('T1','missing')]));
bad.push(operation('week-10',[measurements('T1','missing')]));
for(const item of bad)assert.throws(()=>prepareVisitEdit(evaluate,added,item));
assert.deepEqual(source,original);
let revision=0,applied=[];const planner=createVisitPlanner(evaluate,()=>revision,result=>applied.push(result));
const preview=planner.preview(added,input);preview.changes[0].after.state='mutated';assert.equal(applied.length,0);
revision++;assert.throws(()=>planner.apply());
planner.preview(added,input);assert.throws(()=>planner.preview(added,bad[0]));assert.equal(planner.canApply(),false);
planner.preview(added,input);planner.invalidate();assert.throws(()=>planner.apply());
planner.preview(added,input);planner.apply();assert.deepEqual(applied[0].sources,completed.sources);
assert.equal(applied[0].summary.changes[0].after.state,'measured');assert.throws(()=>planner.apply());
process.stdout.write(JSON.stringify({status:'passed',supported_states:5,rejected_operations:bad.length,native_cases:native,
 checks:['complete ordered target replacement preserves study text and other visits','state-dependent values and Unicode/multiline reasons retain native semantics','omitted targets are made explicit without inferring measurements','strict fields, precision and reasons use core validation; stale previews and changed forms cannot apply']}));
