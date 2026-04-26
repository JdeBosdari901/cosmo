// Shared picker library — unchanged from v1.
export function pickRecipe(input) {
  if (!input.pack && !input.collection) {
    throw new Error("pickRecipe: exactly one of `pack` or `collection` must be set");
  }
  if (input.pack && input.collection) {
    throw new Error("pickRecipe: `pack` and `collection` are mutually exclusive");
  }
  if (input.requestedQuantity <= 0) {
    throw new Error(`pickRecipe: requestedQuantity must be > 0, got ${input.requestedQuantity}`);
  }
  return input.pack ? pickPackOfN(input, input.pack) : pickCollection(input, input.collection);
}
function pickPackOfN(input, bom) {
  const { requestedQuantity, allocatableSnapshot } = input;
  const { component_sku, bom_multiplier } = bom;
  if (bom_multiplier <= 0) {
    throw new Error(`pickRecipe: bom_multiplier must be > 0, got ${bom_multiplier}`);
  }
  const allocatable = allocatableSnapshot.get(component_sku) ?? 0;
  const needed = requestedQuantity * bom_multiplier;
  if (allocatable >= needed) {
    return {
      kind: "ok",
      recipe: [
        {
          single_sku: component_sku,
          qty_per_pack: bom_multiplier,
          segment_name: null
        }
      ]
    };
  }
  const primaryQuantity = Math.floor(allocatable / bom_multiplier);
  const shortfallQuantity = requestedQuantity - primaryQuantity;
  return {
    kind: "split",
    primaryRecipe: primaryQuantity > 0 ? [
      {
        single_sku: component_sku,
        qty_per_pack: bom_multiplier,
        segment_name: null
      }
    ] : [],
    primaryQuantity,
    shortfallQuantity
  };
}
function pickCollection(input, ctx) {
  const { requestedQuantity, allocatableSnapshot } = input;
  const { colourMap, segmentConfig } = ctx;
  const segments = [
    ...segmentConfig.segments
  ].sort((a, b)=>a.segment_order - b.segment_order);
  const segmentMembers = new Map();
  for (const seg of segments){
    segmentMembers.set(seg.segment_name, []);
  }
  for (const [sku, info] of colourMap.entries()){
    if (!info.in_cottage_pool) continue;
    const bucket = segmentMembers.get(info.colour_category);
    if (!bucket) continue;
    const allocatable = allocatableSnapshot.get(sku) ?? 0;
    bucket.push({
      single_sku: sku,
      allocatable
    });
  }
  for (const list of segmentMembers.values()){
    list.sort((a, b)=>b.allocatable - a.allocatable || a.single_sku.localeCompare(b.single_sku));
  }
  const states = segments.map((spec)=>{
    const qty_base = spec.qty_per_pack_fixed ?? 1;
    const normalThreshold = qty_base * requestedQuantity + spec.singles_floor;
    const members = segmentMembers.get(spec.segment_name) ?? [];
    const eligibleForNormal = members.filter((m)=>m.allocatable >= normalThreshold);
    const totalAllocatable = members.reduce((acc, m)=>acc + Math.max(0, m.allocatable), 0);
    return {
      spec,
      qty_base,
      members,
      eligibleForNormal,
      totalAllocatable
    };
  });
  const emptySegments = states.filter((s)=>s.eligibleForNormal.length === 0);
  const nonEmptySegments = states.filter((s)=>s.eligibleForNormal.length > 0);
  const emptyCount = emptySegments.length;
  const tolerance = Math.min(...states.map((s)=>s.spec.emptiness_tolerance));
  if (emptyCount > tolerance) {
    return {
      kind: "needs_decision",
      reason: "too_many_empty_segments",
      diagnostics: {
        collection_sku: segmentConfig.collection_sku,
        empty_count: emptyCount,
        emptiness_tolerance: tolerance,
        empty_segments: emptySegments.map((s)=>s.spec.segment_name)
      }
    };
  }
  if (emptyCount === 0) {
    const recipe = states.map((s)=>({
        single_sku: s.eligibleForNormal[0].single_sku,
        qty_per_pack: s.qty_base,
        segment_name: s.spec.segment_name
      }));
    return {
      kind: "ok",
      recipe
    };
  }
  const ranked = [
    ...nonEmptySegments
  ].sort((a, b)=>b.totalAllocatable - a.totalAllocatable || a.spec.segment_order - b.spec.segment_order);
  const doublerSlots = new Set(ranked.slice(0, emptyCount).map((s)=>s.spec.segment_name));
  const failed = [];
  for (const segName of doublerSlots){
    const s = states.find((x)=>x.spec.segment_name === segName);
    const doublerThreshold = 2 * s.qty_base * requestedQuantity + s.spec.singles_floor;
    const best = s.members[0];
    if (!best || best.allocatable < doublerThreshold) {
      failed.push(segName);
    }
  }
  if (failed.length > 0) {
    return {
      kind: "needs_decision",
      reason: "no_viable_doubler",
      diagnostics: {
        collection_sku: segmentConfig.collection_sku,
        empty_count: emptyCount,
        doubler_slots_needed: Array.from(doublerSlots),
        doubler_slots_unfillable: failed
      }
    };
  }
  const recipe = [];
  for (const s of states){
    if (s.eligibleForNormal.length === 0) continue;
    const isDoubler = doublerSlots.has(s.spec.segment_name);
    const best = s.members[0];
    recipe.push({
      single_sku: best.single_sku,
      qty_per_pack: isDoubler ? 2 * s.qty_base : s.qty_base,
      segment_name: s.spec.segment_name
    });
  }
  return {
    kind: "ok",
    recipe
  };
}
