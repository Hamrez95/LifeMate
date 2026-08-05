# LifeMate authentication experience refresh

This change translates the six approved WellMate and CareMate references into
native Flutter UI. The screenshots are treated as visual direction, not runtime
background images, so the final screens retain keyboard support, validation,
RTL, text scaling, semantics and real Supabase authentication.

## Product mapping

- **CareMate / blue:** family-care language, heart motifs, calm blue glass card.
- **WellMate / green:** treatment-plan language, leaf and health motifs. It does
  not use “companion” copy that could blur the distinction with CareMate.
- Login and sign-up stay in one animated segmented surface.
- The account-preparation screen appears only for the real bootstrap duration;
  no artificial delay is introduced.
- While bootstrap is running, one of 100 reviewed general wellbeing facts is
  selected randomly and rotates every 2.4 seconds.

## Motion

- Subtle floating background ornaments and waves.
- Fade/slide entrance for the authentication surface.
- Animated login/sign-up selection and field transition.
- Orbiting brand logo and animated preparation stages.
- Reduced visual intensity on blocking and preparation states.

## Safety and accessibility

- Existing request timeouts, password recovery, auth error mapping and Google
  provider feature flag remain fail-closed.
- Facts are general educational prompts and explicitly state that they do not
  replace medical advice.
- No screenshot is used as an interactive form.
- Inputs preserve autofill hints, validation, RTL/LTR handling and semantics.
