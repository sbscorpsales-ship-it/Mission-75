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
  const VERSION = "1.1.0";
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
  // Moore et al. (2021) simple cadence metabolic equation; level walking.
  // VO2 ml/kg/min = 1.811 + 0.02014*C + 0.0007427*C^2.
  function estimateWalkingMETFromCadence(cadenceSpm) {
    if (!finite(cadenceSpm)||cadenceSpm<40||cadenceSpm>140) return null;
    const vo2=1.811+0.02014*cadenceSpm+0.0007427*cadenceSpm*cadenceSpm;
    return clamp(vo2/3.5,1,16);
  }
  function estimateMET({speedKmh,grade=0,cadenceSpm=null}) {
    if (!finite(speedKmh)||speedKmh<=0) return null;
    const g=clamp(finite(grade)?grade:0,-0.10,0.15);
    const v=speedKmh*1000/60;
    const met=speedKmh>=3&&speedKmh<=6
      ? (0.1*v+1.8*v*g+3.5)/3.5
      : interpolate(speedKmh)+(1.8*v*g)/3.5;
    return clamp(met,1,16);
  }
  function classifyIntensity({met=null,cadenceSpm=null,heartRateBpm=null,ageYears=null,activityType="walking"}) {
    if (finite(heartRateBpm)&&finite(ageYears)&&ageYears>=18&&ageYears<=100) {
      const ratio=heartRateBpm/(205.8-0.685*ageYears);
      return {intensity:ratio>=0.70?"vigorous":ratio>=0.50?"moderate":"light",source:"heart_rate"};
    }
    if (finite(met)) return {intensity:met>=6?"vigorous":met>=3?"moderate":"light",source:"met_estimate"};
    if (activityType==="walking"&&finite(cadenceSpm)) {
      return {intensity:cadenceSpm>=130?"vigorous":cadenceSpm>=100?"moderate":"light",source:"cadence_threshold"};
    }
    return {intensity:"light",source:"none"};
  }
  function calculateActivityPoints({movingMinutes,met=null,cadenceSpm=null,heartRateBpm=null,ageYears=null,activityType="walking"}) {
    if (!finite(movingMinutes)||movingMinutes<=0) return {points:0,moderateMinutes:0,vigorousMinutes:0,source:"unavailable"};
    const c=classifyIntensity({met,cadenceSpm,heartRateBpm,ageYears,activityType});
    const moderateMinutes=c.intensity==="moderate"?Math.floor(movingMinutes):0;
    const vigorousMinutes=c.intensity==="vigorous"?Math.floor(movingMinutes):0;
    return {points:moderateMinutes+2*vigorousMinutes,moderateMinutes,vigorousMinutes,source:c.source};
  }
  // Interval inputs preserve intensity changes within a mixed-pace walk.
  function calculateActivityPointsForIntervals({intervals,ageYears=null}) {
    if (!Array.isArray(intervals)||intervals.length===0) return {points:0,moderateMinutes:0,vigorousMinutes:0,source:"unavailable"};
    let moderateSeconds=0, vigorousSeconds=0, used=0, sources=new Set();
    for (const interval of intervals) {
      if (!interval||!finite(interval.durationSeconds)||interval.durationSeconds<=0) continue;
      const c=classifyIntensity({...interval,ageYears:interval.ageYears??ageYears});
      if (c.intensity==="moderate") moderateSeconds+=interval.durationSeconds;
      if (c.intensity==="vigorous") vigorousSeconds+=interval.durationSeconds;
      if (c.source!=="none") sources.add(c.source);
      used+=interval.durationSeconds;
    }
    const moderateMinutes=Math.floor(moderateSeconds/60), vigorousMinutes=Math.floor(vigorousSeconds/60);
    return {points:moderateMinutes+2*vigorousMinutes,moderateMinutes,vigorousMinutes,classifiedSeconds:used,source:[...sources].join("+")||"none"};
  }
  function estimateActivity(input) {
    const w=input&&input.weightKg, mins=input&&input.movingMinutes;
    if (!finite(w)||w<25||w>300) throw new RangeError("weightKg must be between 25 and 300 kg");
    if (!finite(mins)||mins<=0||mins>1440) throw new RangeError("movingMinutes must be >0 and <=1440");
    const speedAvailable=finite(input.speedKmh)&&input.speedKmh>0;
    const cadenceFallback=!speedAvailable&&(input.activityType??"walking")==="walking";
    const met=speedAvailable
      ? estimateMET({speedKmh:input.speedKmh,grade:input.grade??0,cadenceSpm:input.cadenceSpm??null})
      : cadenceFallback?estimateWalkingMETFromCadence(input.cadenceSpm):null;
    if (met===null) return {engineVersion:VERSION,status:"insufficient_data",activeCaloriesKcal:null,grossCaloriesKcal:null,met:null,calculationMethod:"none"};
    const gross=met*3.5*w*mins/200, resting=3.5*w*mins/200, active=Math.max(0,gross-resting);
    const points=calculateActivityPoints({movingMinutes:mins,met,heartRateBpm:input.heartRateBpm??null,ageYears:input.ageYears??null,activityType:input.activityType??"walking"});
    return {engineVersion:VERSION,status:"estimated",activeCaloriesKcal:Math.round(active),grossCaloriesKcal:Math.round(gross),met:Math.round(met*100)/100,movingMinutes:Math.round(mins*10)/10,activityPoints:points.points,intensitySource:points.source,intensityMinutes:points.moderateMinutes+points.vigorousMinutes,moderateMinutes:points.moderateMinutes,vigorousMinutes:points.vigorousMinutes,calculationMethod:speedAvailable?"speed_grade_met":"cadence_met"};
  }
  function estimateDistanceFromSteps({steps,strideLengthMeters}) {
    if (!Number.isInteger(steps)||steps<0) throw new RangeError("steps must be a non-negative integer");
    if (!finite(strideLengthMeters)||strideLengthMeters<0.3||strideLengthMeters>1.5) throw new RangeError("strideLengthMeters must be 0.3–1.5 m");
    return Math.round(steps*strideLengthMeters);
  }
  function ringProgress(value,goal) { return !finite(value)||!finite(goal)||goal<=0?0:clamp(value/goal,0,1); }
  return {VERSION,estimateMET,estimateWalkingMETFromCadence,estimateActivity,calculateActivityPoints,calculateActivityPointsForIntervals,estimateDistanceFromSteps,ringProgress};
});
