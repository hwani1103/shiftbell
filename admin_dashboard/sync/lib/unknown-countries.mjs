// Unknown-country metrics are queried as a union in GA4, never added locally.
export const UNKNOWN_COUNTRY = '(not set)';
export const isUnknownCountry = value => value == null || !String(value).trim() || value === '(not set)' || value === '(missing)';
export const hasUnknownCountry = (report,index=0) => (report?.rows ?? []).some(row=>isUnknownCountry(row.dimensionValues?.[index]?.value));

export function mergeUnknownCountryReport(original,union,index=0) {
  if(!original || !union) return original;
  const rows=(original.rows ?? []).filter(row=>!isUnknownCountry(row.dimensionValues?.[index]?.value));
  for(const row of union.rows ?? []) {
    const dimensions=[...(row.dimensionValues ?? [])];
    dimensions.splice(index,0,{value:UNKNOWN_COUNTRY});
    rows.push({...row,dimensionValues:dimensions});
  }
  const truncated=Number(original.rowCount ?? 0)>(original.rows?.length ?? 0) || Number(union.rowCount ?? 0)>(union.rows?.length ?? 0);
  return {...original,rows,rowCount:rows.length,metadata:{
    ...original.metadata,
    subjectToThresholding:original.metadata?.subjectToThresholding===true || union.metadata?.subjectToThresholding===true,
    dataLossFromOtherRow:original.metadata?.dataLossFromOtherRow===true || union.metadata?.dataLossFromOtherRow===true,
    sourceTruncated:truncated,
    samplingMetadatas:[...(original.metadata?.samplingMetadatas ?? []),...(union.metadata?.samplingMetadatas ?? [])],
  }};
}
