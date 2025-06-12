# GitHub Resume Scanner

A comprehensive Ruby tool that analyzes your GitHub repositories to generate detailed resume-ready insights, technical skill assessments, and professional development metrics.

## Features

### Resume Context Building
- **Technical Skills Analysis**: Programming languages with experience levels
- **Technology Stack Detection**: Frameworks, databases, cloud platforms, tools
- **Professional Indicators**: Documentation quality, testing practices, collaboration metrics
- **Career Timeline**: Years active, project consistency, maintenance commitment
- **Architectural Patterns**: Full-stack, microservices, API-first detection

### Output Formats
- **Resume Snippet**: Professional markdown resume section
- **Skills Summary**: Structured JSON for easy integration
- **Detailed Insights**: Comprehensive analytics for deep analysis
- **Repository Reports**: Individual project breakdowns

### Analysis Capabilities
- Language expertise with project count and recency
- Framework and technology detection
- Project quality scoring
- Collaboration experience assessment
- Open source contribution tracking
- Career progression timeline

## Installation

### Prerequisites
- Ruby 2.7 or higher
- GitHub Personal Access Token

### Setup

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd gh-repository-info
   ```

2. **Install dependencies:**
   ```bash
   bundle install
   ```

3. **Set up your GitHub token:**
   ```bash
   # Get your token from: https://github.com/settings/tokens
   # Required scopes: 'repo' (for private repos) or 'public_repo' (for public only)
   export GITHUB_TOKEN='your_github_token_here'
   ```

## Usage

### Basic Usage

```bash
# Scan all repositories
ruby scan.rb

# Limit to specific number of repos
ruby scan.rb --limit 10

# Skip forks and archived repositories
ruby scan.rb --skip-forks --skip-archived

# Filter by programming language
ruby scan.rb --language JavaScript

# Set minimum stars threshold
ruby scan.rb --min-stars 5

# Custom output directory
ruby scan.rb --output my_resume_scan_2025
```

### Command Line Options

| Option | Description | Example |
|--------|-------------|---------|
| `-l, --limit N` | Limit number of repositories | `--limit 20` |
| `-s, --skip-forks` | Skip forked repositories | `--skip-forks` |
| `-a, --skip-archived` | Skip archived repositories | `--skip-archived` |
| `-L, --language LANG` | Filter by programming language | `--language Python` |
| `-m, --min-stars N` | Minimum stars required | `--min-stars 10` |
| `-o, --output DIR` | Output directory | `--output resume_2025` |
| `-h, --help` | Show help message | `--help` |

## Output Files

### Directory Structure
```
resume_repo_scan_2025-06-11/
├── complete_summary.json      # Full analysis data
├── resume_insights.json       # Detailed resume metrics
├── resume_snippet.md         # Professional resume section
├── skills_summary.json       # Structured skills data
├── user_profile.json         # GitHub profile info
└── repositories/
    ├── repo1/
    │   ├── repo_info.json
    │   ├── languages.json
    │   ├── contributors.json
    │   ├── tree_structure.txt
    │   └── README.md
    └── repo2/...
```

## Example Output

### Resume Snippet (`resume_snippet.md`)

```markdown
# GitHub Portfolio Summary

**Generated:** June 11, 2025

## Professional Summary
- **Total Repositories:** 25
- **Total Stars Earned:** 342
- **Total Contributions:** 1,247
- **Years Active:** 8.3
- **Consistency Score:** 92.5%
- **Member Since:** July 2011

## Technical Skills

### Programming Languages
- **JavaScript** - Expert (12 projects)
- **Python** - Proficient (8 projects)
- **TypeScript** - Proficient (6 projects)
- **Rust** - Intermediate (3 projects)
- **Go** - Intermediate (2 projects)

### Frameworks
- **React** (8 projects)
- **Express.js** (5 projects)
- **Django** (3 projects)
- **Next.js** (2 projects)

### Databases
- **MongoDB** (6 projects)
- **PostgreSQL** (4 projects)
- **Redis** (3 projects)

### Cloud Platforms
- **AWS** (5 projects)
- **Vercel** (3 projects)
- **Heroku** (2 projects)

### Tools And Practices
- **Docker** (7 projects)
- **CI/CD** (9 projects)
- **Testing** (12 projects)
- **TypeScript** (6 projects)
- **REST API** (8 projects)

## Professional Development
- **Documentation Quality:** 95.2%
- **Testing Practices:** 76.0%
- **Project Organization:** 88.0%
- **Collaboration Experience:** 8 projects
- **Active Maintenance:** 72.0%

## Notable Projects

### awesome-framework
A modern web framework built with TypeScript
- 156 stars

### data-visualization-tool
Interactive dashboard for complex data analysis
- 89 stars

### microservice-template
Production-ready microservice boilerplate
- 67 stars

## Development Activity
- **Active Projects:** 18
- **Long-term Projects:** 8 (12+ months)
- **Avg Commits/Project:** 52.3

## Architectural Experience
- Full-Stack
- Microservices
- API-First
```

### Skills Summary (`skills_summary.json`)

```json
{
  "technical_skills": {
    "programming_languages": [
      "JavaScript",
      "Python", 
      "TypeScript",
      "Rust",
      "Go"
    ],
    "frameworks": [
      "React",
      "Express.js",
      "Django",
      "Next.js"
    ],
    "databases": [
      "MongoDB",
      "PostgreSQL", 
      "Redis"
    ],
    "cloud_platforms": [
      "AWS",
      "Vercel",
      "Heroku"
    ],
    "tools_and_practices": [
      "Docker",
      "CI/CD",
      "Testing",
      "TypeScript",
      "REST API"
    ]
  },
  "experience_metrics": {
    "years_active": 8.3,
    "total_projects": 25,
    "consistency_score": 92.5,
    "stars_earned": 342
  },
  "professional_indicators": {
    "documentation_quality": 95.2,
    "testing_practices": 76.0,
    "collaboration_experience": 8,
    "maintenance_commitment": 72.0
  },
  "architectural_patterns": [
    "Full-Stack",
    "Microservices", 
    "API-First"
  ],
  "top_repositories": [
    "awesome-framework",
    "data-visualization-tool",
    "microservice-template"
  ]
}
```

### Sample Console Output

```
Scanning repositories for: your-username
Name: Your Name
Bio: Full-stack developer passionate about open source
Location: San Francisco, CA
--------------------------------------------------

Found 45 repositories after filtering
Processing limit: 25

[1/25] Processing: your-username/awesome-framework
  ✓ Languages analyzed
  ✓ Topics fetched: javascript, typescript, framework, web
  ✓ Contributors analyzed (12 total)
  ✓ Commit history analyzed
  ✓ README saved
  ✓ Tree structure saved (simplified)
  ✓ Pull requests analyzed
  ✓ Issues analyzed

[2/25] Processing: your-username/data-viz-tool
  ✓ Languages analyzed
  ✓ Contributors analyzed (3 total)
  ✓ Commit history analyzed
  ✓ README saved
  ✓ Tree structure saved (simplified)
  ✓ Pull requests analyzed
  ✓ Issues analyzed

...

✅ Scan complete! Results saved to 'resume_repo_scan_2025-06-11' directory
```

## Technology Detection

The scanner automatically detects technologies based on:

### Programming Languages
- Repository primary language
- Language distribution in codebase
- File extensions and patterns

### Frameworks & Libraries
- Package.json dependencies
- Gemfile contents
- Requirements.txt files
- Import statements
- Project structure patterns

### Development Practices
- Test file detection (jest, pytest, rspec, etc.)
- CI/CD configuration files
- Docker containers
- Documentation quality
- Code organization

### Professional Indicators
- **Documentation Quality**: README completeness, inline documentation
- **Testing Practices**: Test coverage, testing frameworks usage
- **Project Organization**: File structure, configuration files, licenses
- **Collaboration**: Multi-contributor projects, PR activity
- **Maintenance**: Recent commits, issue resolution, release management

## Use Cases

### Resume Building
- Generate professional technical skills sections
- Quantify programming experience with metrics
- Showcase project diversity and complexity
- Demonstrate professional development practices

### Portfolio Websites
- Structured data for dynamic skill displays
- Project highlights with metrics
- Technology expertise visualization
- Professional achievement tracking

### Technical Interviews
- Comprehensive skill inventory
- Project-based discussion points
- Technical depth assessment
- Experience level validation

### Career Development
- Skill gap identification
- Technology trend tracking
- Professional growth metrics
- Learning path planning

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

If you encounter any issues or have questions:

1. Check the [Issues](https://github.com/your-repo/issues) page
2. Create a new issue with detailed information
3. Include your Ruby version and sample output

---

**Made with love for developers who want to showcase their GitHub contributions professionally.**

## Real Example from Your Repositories

### Actual Output from oeo's Repositories

Based on the scan of your top 5 repositories:

```markdown
# GitHub Portfolio Summary

**Generated:** June 11, 2025

## Professional Summary
- **Total Repositories:** 5
- **Total Stars Earned:** 70
- **Total Contributions:** 391
- **Years Active:** 8.3
- **Consistency Score:** 90.0%
- **Member Since:** July 2011

## Technical Skills

### Programming Languages
- **HTML** - Intermediate (2 projects)
- **CoffeeScript** - Proficient (3 projects)
- **JavaScript** - Intermediate (2 projects)
- **Rust** - Intermediate (2 projects)
- **Shell** - Intermediate (4 projects)

### Tools And Practices
- **REST API** (1 projects)

## Notable Projects

### ward
a personal file vault written in bash
- 29 stars

### xdomls
crossdomain for localstorage
- 16 stars

### bolt
bolt is a blockchain.
- 12 stars

### mkay
an opinionated node m/v/route api framework for rapid development
- 7 stars
```

This demonstrates how the scanner analyzes real repositories to extract meaningful resume insights!