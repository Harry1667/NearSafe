# HavenCircle contributor guide

## Product guardrails

- HavenCircle is a family safety-awareness product, not an emergency service. Keep the non-emergency disclaimer and clear 110 / 119 escalation path visible where relevant.
- Never imply live family tracking. Store and present saved places and alert radii only.
- Do not rely on color alone for risk or verification state; every status needs a plain-language label.
- Treat community information as unverified unless an official source or corroboration is explicitly represented.
- Prefer approximate event locations in UI and avoid collecting unnecessary personal data.

## Engineering conventions

- Keep the prototype self-contained, deterministic, and usable in Xcode previews.
- Use SwiftUI and MapKit system APIs before adding third-party dependencies.
- Keep user-facing strings in Traditional Chinese.
- Verify builds with `xcodebuild` after changing Swift source when the local toolchain is available.
