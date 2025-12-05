---
description: Plan and implement a new feature for WPFleet
---

When adding a new feature to WPFleet:

1. **Planning Phase**
   - Understand the feature requirements
   - Identify which scripts need modification
   - Check for existing similar functionality
   - Consider Docker service implications
   - Plan notification/logging integration

2. **Implementation Checklist**
   - [ ] Create or modify necessary scripts
   - [ ] Follow existing code patterns
   - [ ] Add proper error handling
   - [ ] Integrate with notification system (scripts/notify.sh)
   - [ ] Add logging support
   - [ ] Update docker-compose.yml if needed
   - [ ] Update .env.example with new variables
   - [ ] Add documentation to README.md
   - [ ] Make scripts executable (chmod +x)
   - [ ] Test with existing installations

3. **Documentation Requirements**
   - Add feature description to README.md
   - Include usage examples
   - Document environment variables
   - Add troubleshooting section if needed

4. **Testing**
   - Test clean install scenario
   - Test upgrade scenario
   - Verify notification integration
   - Check error conditions
   - Validate with docker-compose config

Proceed with implementing the requested feature following this checklist.
