const assert = require("node:assert/strict");
const e = require("./gativx-activity-engine.js");
function near(a,b,t,label){assert.ok(Math.abs(a-b)<=t,label+": expected "+b+" ± "+t+", got "+a);}
const brisk=e.estimateActivity({weightKg:70,movingMinutes:30,speedKmh:5,grade:0,cadenceSpm:112});
near(brisk.met,3.38,0.02,"brisk walking MET");
near(brisk.activeCaloriesKcal,88,1,"brisk walking active kcal");
assert.equal(brisk.activityPoints,30);
assert.equal(brisk.intensitySource,"met_estimate");
assert.equal(e.calculateActivityPoints({movingMinutes:20,met:6.2}).points,40);
assert.equal(e.calculateActivityPoints({movingMinutes:12,heartRateBpm:120,ageYears:40,met:2}).points,12);
assert.equal(e.calculateActivityPoints({movingMinutes:15,met:2.5,cadenceSpm:85}).points,0);
assert.equal(e.estimateDistanceFromSteps({steps:1000,strideLengthMeters:0.72}),720);
assert.equal(e.ringProgress(120,100),1);
assert.equal(e.ringProgress(25,100),0.25);
const missing=e.estimateActivity({weightKg:70,movingMinutes:30,speedKmh:null});
assert.equal(missing.status,"insufficient_data");
assert.equal(missing.activeCaloriesKcal,null);
const cadenceOnly=e.estimateActivity({weightKg:70,movingMinutes:30,speedKmh:null,cadenceSpm:100,activityType:"walking"});
assert.equal(cadenceOnly.status,"estimated");
assert.equal(cadenceOnly.calculationMethod,"cadence_met");
near(cadenceOnly.met,3.21,0.02,"cadence-only walking MET");
assert.ok(cadenceOnly.activeCaloriesKcal>0);
assert.equal(e.estimateWalkingMETFromCadence(0),null);
const mixed=e.calculateActivityPointsForIntervals({intervals:[
  {durationSeconds:300,met:2.5},
  {durationSeconds:600,met:3.5},
  {durationSeconds:300,met:6.5}
]});
assert.equal(mixed.moderateMinutes,10);
assert.equal(mixed.vigorousMinutes,5);
assert.equal(mixed.points,20);
assert.throws(()=>e.estimateActivity({weightKg:0,movingMinutes:30,speedKmh:5}),RangeError);
console.log("GATIVX activity engine tests passed");
