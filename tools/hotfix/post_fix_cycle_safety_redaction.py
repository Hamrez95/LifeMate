from pathlib import Path

path = Path(__file__).resolve().parents[2] / "supabase/functions/lifemate-api/women_calendar.ts"
text = path.read_text(encoding="utf-8")

invalid_call = """    ovulationDay: fertilityEstimateReliable ? ovulationDay : null,
    fertileWindowStartDay: fertilityEstimateReliable ? fertileWindowStartDay : null,
    fertileWindowEndDay: fertilityEstimateReliable ? fertileWindowEndDay : null,
    pmsStartDay,"""
plain_call = """    ovulationDay,
    fertileWindowStartDay,
    fertileWindowEndDay,
    pmsStartDay,"""

if invalid_call not in text:
    raise SystemExit("Expected temporary redaction in phaseForCycleDay call was not found")
text = text.replace(invalid_call, plain_call, 1)

return_old = """    detailedPhase,
    ovulationDay,
    fertileWindowStartDay,
    fertileWindowEndDay,
    pmsStartDay,"""
return_new = """    detailedPhase,
    ovulationDay: fertilityEstimateReliable ? ovulationDay : null,
    fertileWindowStartDay: fertilityEstimateReliable ? fertileWindowStartDay : null,
    fertileWindowEndDay: fertilityEstimateReliable ? fertileWindowEndDay : null,
    pmsStartDay,"""

if return_old not in text:
    raise SystemExit("Expected estimate return fields were not found")
text = text.replace(return_old, return_new, 1)
path.write_text(text, encoding="utf-8")
