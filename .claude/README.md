# Claude Configuration for WPFleet

This directory contains Claude Code configuration and custom commands for the WPFleet project.

## Configuration

The `claude.json` file provides project context to Claude, including:
- Project description and architecture
- Development guidelines
- Technology stack information
- Code organization structure

## Custom Commands

Use these slash commands in Claude Code to streamline common tasks:

### `/review-script`
Review a bash script for best practices, security issues, and improvements.

**Usage:**
```
/review-script
```
Then specify which script file you want reviewed.

### `/add-feature`
Get a structured checklist and guidance for implementing a new feature.

**Usage:**
```
/add-feature
```
Describe the feature you want to add, and Claude will guide you through the implementation.

### `/check-health`
Perform a comprehensive health check of the entire project.

**Usage:**
```
/check-health
```
Analyzes scripts, Docker configuration, documentation, security, and best practices.

### `/debug-issue`
Systematically debug a problem in WPFleet.

**Usage:**
```
/debug-issue
```
Describe the issue you're experiencing for systematic troubleshooting.

## Benefits

- **Context Awareness**: Claude understands WPFleet's architecture and conventions
- **Consistency**: Follows project-specific guidelines and patterns
- **Efficiency**: Custom commands provide structured workflows for common tasks
- **Quality**: Built-in best practices and security checks

## Extending

To add new custom commands:

1. Create a new `.md` file in `.claude/commands/`
2. Add a description in the frontmatter:
   ```markdown
   ---
   description: Your command description
   ---
   ```
3. Write the command prompt content
4. Use it with `/your-command-name`

For more information about Claude Code configuration, visit the [Claude Code documentation](https://github.com/anthropics/claude-code).
