---
description: Analyze project health, dependencies, and potential issues
---

Perform a comprehensive health check of the WPFleet project:

1. **Script Analysis**
   - List all scripts and their purposes
   - Check for consistent error handling patterns
   - Identify scripts missing executable permissions
   - Verify shared library usage

2. **Docker Configuration**
   - Review docker-compose.yml structure
   - Check service dependencies
   - Verify volume mounts
   - Review resource limits
   - Check network configuration

3. **Documentation**
   - Verify README.md is up to date
   - Check .env.example completeness
   - Identify undocumented features
   - Find missing usage examples

4. **Security**
   - Review credential handling
   - Check file permissions
   - Verify container isolation
   - Review exposed ports
   - Check for hardcoded secrets

5. **Best Practices**
   - Shellcheck compliance
   - Consistent logging patterns
   - Error handling coverage
   - Backup and recovery readiness

Provide a detailed report with specific recommendations.
