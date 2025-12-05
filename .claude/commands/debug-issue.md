---
description: Debug a specific issue in WPFleet
---

Debug the reported issue systematically:

1. **Understand the Problem**
   - What is the expected behavior?
   - What is the actual behavior?
   - When did it start occurring?
   - Is it reproducible?

2. **Gather Information**
   - Check relevant script code
   - Review Docker logs (docker logs wpfleet_*)
   - Check service status (docker ps)
   - Review log files in data/logs/
   - Check environment variables

3. **Analyze**
   - Identify the root cause
   - Check for related issues in other scripts
   - Review recent changes (git log)
   - Test in isolation if possible

4. **Propose Solution**
   - Suggest fix with code examples
   - Consider backward compatibility
   - Identify testing requirements
   - Note any breaking changes

5. **Prevention**
   - Suggest improvements to prevent recurrence
   - Recommend additional logging or validation
   - Identify gaps in error handling

Provide detailed analysis and actionable solutions.
