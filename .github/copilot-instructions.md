# Copilot Instructions

## General Guidelines
- Work through each checklist item systematically.
- Keep communication concise and focused.
- Follow development best practices.
- Only build when explicitly requested by the user; do not start a build automatically after every change.
- Perform a debug/validation run before finalizing changes.

## Project Setup
- [x] Verify that the copilot-instructions.md file in the .github directory is created.  
  Summary: File exists in .github.

- [x] Clarify Project Requirements  
  Summary: Flutter app for Arbeitszeiterfassung, Android first, iOS later, widget support prepared.

- [x] Scaffold the Project  
  Summary: Flutter project scaffolded in-place with Android and iOS targets.

- [x] Customize the Project  
  Summary: Replaced template app with work-time tracking baseline (start/stop, daily total, session list, local persistence, widget sync hook).

- [x] Install Required Extensions  
  Summary: No required extensions were specified by setup info.

- [x] Compile the Project  
  Summary: Dependencies installed, analyze passed, tests passed.

- [x] Create and Run Task  
  Summary: VS Code task file created for Flutter tests via Puro.

- [x] Launch the Project  
  Summary: Launch requested and attempted; no Android/iOS device/emulator available in current environment.

- [x] Ensure Documentation is Complete  
  Summary: README updated with setup and current status.

## Project-Specific Rules
- Do not subtract logged shifts from the monthly target hours; logged (normal) shifts must not reduce the required/target hours in the monthly overview.
- Apply this rule consistently in calculations and all UI displays for monthly totals, progress indicators, and exports.
