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


// Boundary and input-quality regression checks.
assert.equal(e.estimateWalkingMETFromCadence(39.99),null);
assert.ok(Number.isFinite(e.estimateWalkingMETFromCadence(40)));
assert.ok(Number.isFinite(e.estimateWalkingMETFromCadence(140)));
assert.equal(e.estimateWalkingMETFromCadence(140.01),null);
assert.equal(e.estimateMET({speedKmh:0,grade:0}),null);
assert.equal(e.estimateMET({speedKmh:-1,grade:0}),null);
near(e.estimateMET({speedKmh:2,grade:0}),2,0.001,"slow walking anchor");
near(e.estimateMET({speedKmh:5,grade:0}),3.38,0.02,"ACSM level walking");
const acsmBoundary=e.estimateMET({speedKmh:6,grade:0});
near(acsmBoundary,13.5/3.5,0.001,"ACSM 6 km/h boundary");
near(e.estimateMET({speedKmh:5.9999,grade:0}),acsmBoundary,0.001,"just below 6 km/h remains continuous");
near(e.estimateMET({speedKmh:6.0001,grade:0}),acsmBoundary,0.002,"just above 6 km/h remains continuous");
assert.equal(e.VERSION,"1.1.2");
near(e.estimateMET({speedKmh:5,grade:0.20}),e.estimateMET({speedKmh:5,grade:0.15}),1e-9,"uphill grade clamp");
near(e.estimateMET({speedKmh:5,grade:-0.20}),e.estimateMET({speedKmh:5,grade:-0.10}),1e-9,"downhill grade clamp");

const moderateHeartRate=e.calculateActivityPoints({movingMinutes:3.9,heartRateBpm:90,ageYears:40,met:2});
assert.equal(moderateHeartRate.moderateMinutes,3);
assert.equal(moderateHeartRate.points,3);
const vigorousHeartRate=e.calculateActivityPoints({movingMinutes:2.9,heartRateBpm:125,ageYears:40,met:2});
assert.equal(vigorousHeartRate.vigorousMinutes,2);
assert.equal(vigorousHeartRate.points,4);
assert.equal(e.calculateActivityPoints({movingMinutes:2,heartRateBpm:125,ageYears:17,met:2}).points,0);

const intervalHeartRate=e.calculateActivityPointsForIntervals({intervals:[
  {durationSeconds:60,met:2,heartRateBpm:125,ageYears:40}
]});
assert.equal(intervalHeartRate.points,2,"valid heart-rate classification takes precedence over MET");
const filteredIntervals=e.calculateActivityPointsForIntervals({intervals:[
  null,
  {durationSeconds:0,met:6},
  {durationSeconds:30,met:3.5},
  {durationSeconds:30,met:3.5},
  {durationSeconds:-5,met:6},
  {durationSeconds:60,met:1.5}
]});
assert.equal(filteredIntervals.moderateMinutes,1);
assert.equal(filteredIntervals.points,1);
assert.equal(filteredIntervals.classifiedSeconds,120);

const nonWalkingCadence=e.estimateActivity({weightKg:70,movingMinutes:20,speedKmh:null,cadenceSpm:110,activityType:"running"});
assert.equal(nonWalkingCadence.status,"insufficient_data");
assert.throws(()=>e.estimateActivity({weightKg:70,movingMinutes:0,speedKmh:5}),RangeError);
assert.throws(()=>e.estimateActivity({weightKg:70,movingMinutes:1441,speedKmh:5}),RangeError);
assert.throws(()=>e.estimateActivity({weightKg:24.9,movingMinutes:30,speedKmh:5}),RangeError);
assert.equal(e.estimateActivity({weightKg:300,movingMinutes:30,speedKmh:5}).status,"estimated");

for (const activityType of ["running", "hiking", "other"]) {
  const unsupported = e.estimateActivity({
    weightKg: 70,
    movingMinutes: 20,
    speedKmh: 5,
    activityType
  });
  assert.equal(unsupported.status, "insufficient_data", activityType + " must not reuse walking MET anchors");
  assert.equal(unsupported.activeCaloriesKcal, null, activityType + " calories must remain unavailable");
  assert.equal(e.estimateMET({speedKmh: 5, activityType}), null, activityType + " speed MET must remain unavailable");
}
assert.equal(e.estimateDistanceFromSteps({steps:0,strideLengthMeters:0.72}),0);
assert.throws(()=>e.estimateDistanceFromSteps({steps:-1,strideLengthMeters:0.72}),RangeError);
assert.throws(()=>e.estimateDistanceFromSteps({steps:1,strideLengthMeters:0.2}),RangeError);
assert.equal(e.ringProgress(Number.NaN,100),0);
assert.equal(e.ringProgress(10,0),0);
assert.equal(e.ringProgress(-1,100),0);

console.log("GATIVX activity engine tests passed");
