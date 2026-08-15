# Security rules tests

Rules failures are silent: an expression that *errors* rather than evaluating
false reads as "permission denied" with no clue which clause broke. Three such
bugs reached a real phone before this existed — a plan that could not be read
before it was created, plan creation blocked by a missing custom claim, and
every avatar upload rejected for the same reason.

These run against the emulator, so they need no Firebase project and touch no
real data.

```bash
cd test_rules
npm install       # once
npm test
```

Requires the Firebase CLI and a JDK (the Firestore emulator is a Java process).
