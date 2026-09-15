# Changelog

## v0.1.1 - 2026-09-15

- Fixed unmatched gomuks direct messages being suppressed before duplicate detection; they now use `visible-chat`.
- Preserved channel filtering, keyword priorities, and global keyword exclusions.
- Clarified direct-message routing and cross-app duplicate suppression in the README and CLI help.

## v0.1.0 - 2026-08-17

- Added configurable `sub:` body rewrites from `dpp.env`, including regex-based attachment filename replacements.
- Applied `dpp.env` substitutions before exclusion, routing, and duplicate checks.
- Documented `dpp.env` substitution rules in the README and built-in `runner.sh --help` output.
