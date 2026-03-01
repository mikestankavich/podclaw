# Contributing to Podclaw

Thank you for your interest in contributing! Podclaw is an experimental lab harness, so contributions that improve safety, idempotency, and observability are especially welcome.

## Ways to Contribute

### 1. Report Issues
- Found a bug in a script or cloud-init? [Open an issue](https://github.com/mikestankavich/podclaw/issues)
- Have a better approach for rootless Podman in Incus? Describe your setup
- Documentation unclear? Let us know

### 2. Submit Pull Requests
- Fix bugs or improve idempotency in scripts
- Add new Incus profiles or cloud-init templates
- Improve documentation and threat model notes
- Add safety checks or linting for cloud-init configs

### 3. Share Your Experience
- How are you running OpenClaw in your homelab?
- What Podman/Incus patterns work well?
- Share your hardening configurations

## Contribution Guidelines

### Code Style
- **Shell scripts**: Follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- **YAML**: Use consistent 2-space indentation
- **Markdown**: Use clear headings and concise language

### Commit Messages
Follow [Conventional Commits](https://www.conventionalcommits.org/):
```
feat: add resource-capped Incus profile
fix: correct subuid/subgid setup in cloud-init
docs: clarify threat model assumptions
```

### Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Make focused, atomic changes
4. Test on Ubuntu 24.04 LTS with Incus if applicable
5. Submit PR with clear description

## Security

If you discover a security issue, please report it privately rather than opening a public issue.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
