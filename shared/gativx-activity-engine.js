/**
 * GATIVX Independent Activity Engine v1
 * Transparent estimates, not medical measurements.
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) root.GATIVXActivityEngine = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";
  const VERSION = "1.0.0";
  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
  const finite = v => typeof v === "number" && Number.isFinite(v);
  const ANCHORS = [[1,1.8],[2,2],[2.5,2.3],[3,2.5],[3.5,2.8],[4,3],[4.5,3.5],[5,3.8],[5.5,4.3],[6,4.8],[6.5,5.5],[7,6],[7.5,6.5],[8,7],[9,8.3],[10,9.8],[11,11],[12,12.5]];
  function interpolate(speed) {
    if (speed <= ANCHORS[0][0]) return ANCHORS[0][1];
    for (let i=1;i<ANCHORS.length;i++) {
      const [rs,rm]=ANCHORS[i], [ls,lm]=ANCHORS[i-1];
      if (speed<=rs) return lm+(rm-lm)*(speed-ls)/(rs-ls);
    }
    return ANCHORS[ANCHORS.length-1][1];
  }
  function estimateMET({speedKmh,grade=0,cadenceSpm=null}) {
    if (!finite(speedKmh)||speedKmh<=0) return null;
    const g=clamp(finite(grade)?grade:0,-0.10,0.15);
    const v=speedKmh*1000/60;
    let met;
    if (speedKmh>=3&&speedKmh<=6) met=(0.1*v+1.8*v*g+3.5)/3.5;
    else met=interpolate(speedKmh)+(1.8*v*g)/3.5;
    if (finite(cadenceSpm)&&cadenceSpm>=100&&speedKmh<=7) met=Math.max(met,cadenceSpm>=130?6:3);
    return clamp(met,1,16);
  }
  function calculateActivityPoints({movingMinutes,met=null,cadenceSpm=null,heartRateBpm=null,ageYears=null,activityType="walking"}) {
    if (!finite(movingMinutes)||movingMinutes<=0) return {points:0,moderateMinutes:0,vigorousMinutes:0,source:"unavailable"};
    let intensity="light",source="none";
    if (finite(heartRateBpm)&&finite(ageYears)&&ageYears>=18&&ageYears<=100) {
      const ratio=heartRateBpm/(205.8-0.685*ageYears);
      intensity=ratio>=0.70?"vigorous":ratio>=0.50?"moderate":"light"; source="heart_rate";
    } else if (finite(met)) {
      intensity=met>=6?"vigorous":met>=3?"moderate":"light"; source="met_estimate";
    } else if (activityType==="walking"&&finite(cadenceSpm)) {
      intensity=cadenceSpm>=130?"vigorous":cadenceSpm>=100?"moderate":"light"; source="cadence_estimate";
    }
    const moderateMinutes=intensity==="moderate"?Math.floor(movingMinutes):0;
    const vigorousMinutes=intensity==="vigorous"?Math.floor(movingMinutes):0;
    return {points:moderateMinutes+2*vigorousMinutes,moderateMinutes,vigorousMinutes,source};
  }
  function estimateActivity(input) {
    const w=input&&input.weightKg, mins=input&&input.movingMinutes;
    if (!finite(w)||w<25||w>300) throw new RangeError("weightKg must be between 25 and 300 kg");
    if (!finite(mins)||mins<=0||mins>1440) throw new RangeError("movingMinutes must be >0 and <=1440");
    const met=estimateMET({speedKmh:input.speedKmh,grade:input.grade??0,cadenceSpm:input.cadenceSpm??null});
    if (met===null) return {engineVersion:VERSION,status:"insufficient_data",activeCaloriesKcal:null,grossCaloriesKcal:null,met:null};
    const gross=met*3.5*w*mins/200, resting=3.5*w*mins/200, active=Math.max(0,gross-resting);
    const points=calculateActivityPoints({movingMinutes:mins,met,cadenceSpm:input.cadenceSpm??null,heartRateBpm:input.heartRateBpm??null,ageYears:input.ageYears??null,activityType:input.activityType??"walking"});
    return {engineVersion:VERSION,status:"estimated",activeCaloriesKcal:Math.round(active),grossCaloriesKcal:Math.round(gross),met:Math.round(met*100)/100,movingMinutes:Math.round(mins*10)/10,activityPoints:points.points,intensitySource:points.source,intensityMinutes:points.moderateMinutes+points.vigorousMinutes,moderateMinutes:points.moderateMinutes,vigorousMinutes:points.vigorousMinutes};
  }
  function estimateDistanceFromSteps({steps,strideLengthMeters}) {
    if (!Number.isInteger(steps)||steps<0) throw new RangeError("steps must be a non-negative integer");
    if (!finite(strideLengthMeters)||strideLengthMeters<0.3||strideLengthMeters>1.5) throw new RangeError("strideLengthMeters must be 0.3–1.5 m");
    return Math.round(steps*strideLengthMeters);
  }
  function ringProgress(value,goal) { return !finite(value)||!finite(goal)||goal<=0?0:clamp(value/goal,0,1); }
  return {VERSION,estimateMET,estimateActivity,calculateActivityPoints,estimateDistanceFromSteps,ringProgress};
});
