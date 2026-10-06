# Security policy

## Supported releases

Security fixes target the latest public release. Development betas named Lungo
or using `app.caffelid.mac` are not supported releases.

## Reporting a vulnerability

Use **Security → Advisories → Report a vulnerability** in this GitHub repository
for a private report. If that button is unavailable, open an issue requesting a
private reporting channel without including exploit details or sensitive data.
Do not publish a working privilege-escalation exploit in an ordinary issue.

Include affected versions, exact macOS version/build, steps to reproduce,
expected impact, and a minimal proof of concept. Do not include passwords,
private signing keys, or unrelated personal files. This is a community project;
there is no guaranteed response time or paid bug bounty.

## Trust boundaries

The GUI runs as the user. Its embedded daemon runs as root under macOS
ServiceManagement. The daemon authenticates the connecting process using a
kernel audit token and an Apple-anchored signature requirement: exact app
identifier and the same signing team as the daemon.

The privileged protocol exposes fixed operations, not arbitrary commands or
paths. The helper uses a root-owned lock, validates legacy installation files
before cleanup, and restores sleep on disconnect and restart. See
[ARCHITECTURE.md](docs/ARCHITECTURE.md) for details and scope.

Battery/temperature limits are application policies, not a replacement for
macOS hardware protections. The temperature reader uses an undocumented
read-only interface; availability depends on hardware and macOS.
