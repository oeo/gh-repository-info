require 'octokit'
require 'json'
require 'fileutils'
require 'base64'
require 'date'
require 'optparse'

class GitHubResumeScanner
  def initialize(token, options = {})
    @client = Octokit::Client.new(access_token: token)
    @client.auto_paginate = true
    @output_dir = options[:output_dir] || "resume_repo_scan_#{Date.today}"
    @limit = options[:limit]
    @skip_forks = options[:skip_forks]
    @skip_archived = options[:skip_archived]
    @filter_language = options[:filter_language]
    @min_stars = options[:min_stars] || 0
  end

  def scan_all_repos
    FileUtils.mkdir_p(@output_dir)

    user = @client.user
    puts "Scanning repositories for: #{user.login}"
    puts "Name: #{user.name}" if user.name
    puts "Bio: #{user.bio}" if user.bio
    puts "Company: #{user.company}" if user.company
    puts "Location: #{user.location}" if user.location
    puts "-" * 50

    # Save user profile
    save_user_profile(user)

    # Get repositories with filtering
    repos = get_filtered_repositories
    puts "\nFound #{repos.length} repositories after filtering"
    puts "Processing limit: #{@limit}" if @limit

    # Limit repos if specified
    repos = repos.first(@limit) if @limit

    summary = {
      scan_date: DateTime.now.iso8601,
      user: {
        login: user.login,
        name: user.name,
        bio: user.bio,
        company: user.company,
        location: user.location,
        blog: user.blog,
        hireable: user.hireable,
        public_repos: user.public_repos,
        followers: user.followers,
        following: user.following,
        created_at: user.created_at
      },
      total_repos: repos.length,
      repositories: [],
      skills_summary: {
        languages: {},
        topics: {},
        total_stars: 0,
        total_forks: 0,
        total_contributions: 0
      }
    }

    repos.each_with_index do |repo, index|
      puts "\n[#{index + 1}/#{repos.length}] Processing: #{repo.full_name}"

      begin
        repo_info = analyze_repository(repo)
        summary[:repositories] << repo_info

        # Aggregate skills data
        update_skills_summary(summary[:skills_summary], repo_info)

        # Add small delay to avoid rate limiting
        sleep(0.5) if index % 10 == 0
      rescue => e
        puts "  ✗ Error processing repository: #{e.message}"
        next
      end
    end

    # Generate resume-friendly insights
    generate_resume_insights(summary)

    # Save summary
    File.write(
      File.join(@output_dir, 'complete_summary.json'),
      JSON.pretty_generate(summary)
    )

    puts "\n✅ Scan complete! Results saved to '#{@output_dir}' directory"
  end

  private

  def get_filtered_repositories
    all_repos = @client.repositories

    filtered = all_repos

    # Apply filters
    filtered = filtered.reject(&:fork) if @skip_forks
    filtered = filtered.reject(&:archived) if @skip_archived
    filtered = filtered.select { |r| r.language == @filter_language } if @filter_language
    filtered = filtered.select { |r| r.stargazers_count >= @min_stars }

    # Sort by stars descending
    filtered.sort_by { |r| -r.stargazers_count }
  end

  def analyze_repository(repo)
    repo_dir = File.join(@output_dir, repo.name.gsub('/', '_'))
    FileUtils.mkdir_p(repo_dir)

    repo_info = {
      # Basic Information
      name: repo.name,
      full_name: repo.full_name,
      description: repo.description,
      url: repo.html_url,
      homepage: repo.homepage,
      created_at: repo.created_at,
      updated_at: repo.updated_at,
      pushed_at: repo.pushed_at,

      # Metrics for resume
      stars: repo.stargazers_count,
      forks: repo.forks_count,
      watchers: repo.watchers_count,
      open_issues: repo.open_issues_count,
      size: repo.size,

      # Technical details
      language: repo.language,
      license: repo.license&.name,
      default_branch: repo.default_branch,
      has_wiki: repo.has_wiki,
      has_pages: repo.has_pages,

      # Resume-relevant flags
      is_fork: repo.fork,
      is_private: repo.private,
      is_archived: repo.archived
    }

    # Get languages breakdown
    begin
      languages = @client.languages(repo.full_name)
      if languages && !languages.empty?
        repo_info[:languages] = languages.to_h
        repo_info[:language_percentages] = calculate_language_percentages(languages.to_h)
        save_data(repo_dir, 'languages.json', languages.to_h)
        puts "  ✓ Languages analyzed"
      end
    rescue => e
      puts "  ✗ Error fetching languages: #{e.message}"
    end

    # Get topics (tags)
    begin
      topics_response = @client.topics(repo.full_name, accept: 'application/vnd.github.mercy-preview+json')
      if topics_response && topics_response[:names]
        repo_info[:topics] = topics_response[:names]
        puts "  ✓ Topics fetched: #{topics_response[:names].join(', ')}" unless topics_response[:names].empty?
      end
    rescue => e
      puts "  ✗ Error fetching topics: #{e.message}"
    end

    # Get contributors
    begin
      contributors = @client.contributors(repo.full_name)
      if contributors && contributors.any?
        repo_info[:total_contributors] = contributors.length
        repo_info[:top_contributors] = contributors.first(5).map do |c|
          {
            login: c.login,
            contributions: c.contributions,
            url: c.html_url
          }
        end

        # Find user's contributions
        user_contrib = contributors.find { |c| c.login == @client.user.login }
        repo_info[:user_contributions] = user_contrib&.contributions || 0

        save_data(repo_dir, 'contributors.json', repo_info[:top_contributors])
        puts "  ✓ Contributors analyzed (#{contributors.length} total)"
      end
    rescue => e
      puts "  ✗ Error fetching contributors: #{e.message}"
    end

    # Get commit activity
    begin
      # Get recent commits
      commits = @client.commits(repo.full_name, per_page: 100)
      if commits && commits.any?
        repo_info[:total_commits] = commits.length

        # Analyze commit frequency
        commit_dates = commits.map { |c| c.commit.author.date }
        repo_info[:first_commit] = commit_dates.last
        repo_info[:last_commit] = commit_dates.first
        repo_info[:commit_frequency] = analyze_commit_frequency(commit_dates)

        puts "  ✓ Commit history analyzed"
      end
    rescue => e
      puts "  ✗ Error fetching commits: #{e.message}"
    end

    # Get releases
    begin
      releases = @client.releases(repo.full_name)
      if releases && releases.any?
        repo_info[:total_releases] = releases.length
        repo_info[:latest_release] = releases.first&.tag_name
        repo_info[:releases] = releases.first(5).map do |r|
          {
            tag_name: r.tag_name,
            name: r.name,
            published_at: r.published_at,
            downloads: r.assets.sum { |a| a.download_count }
          }
        end
        puts "  ✓ Releases analyzed (#{releases.length} total)"
      end
    rescue => e
      puts "  ✗ Error fetching releases: #{e.message}"
    end

    # Get README
    begin
      readme = @client.readme(repo.full_name)
      if readme && readme.content
        readme_content = Base64.decode64(readme.content)
        save_data(repo_dir, 'README.md', readme_content, binary: true)
        repo_info[:has_readme] = true
        repo_info[:readme_size] = readme_content.length
        puts "  ✓ README saved"
      end
    rescue => e
      repo_info[:has_readme] = false
      puts "  ✗ No README found"
    end

    # Get tree structure with improved error handling
    begin
      # Get repository contents first to verify structure
      root_contents = @client.contents(repo.full_name)
      
      if root_contents && root_contents.any?
        # Count files and directories from root contents
        repo_info[:total_files] = root_contents.count { |item| item.type == 'file' }
        repo_info[:total_directories] = root_contents.count { |item| item.type == 'dir' }
        
        # Analyze file types from root contents
        file_extensions = root_contents
          .select { |item| item.type == 'file' }
          .map { |item| File.extname(item.name).downcase }
          .reject(&:empty?)
          .tally
        
        repo_info[:file_types] = file_extensions if file_extensions.any?
        
        # Create simplified tree structure from contents
        tree_structure = root_contents.map { |item| 
          "#{item.type == 'dir' ? '📁' : '📄'} #{item.name}"
        }.join("\n")
        
        save_data(repo_dir, 'tree_structure.txt', tree_structure)
        puts "  ✓ Tree structure saved (simplified)"
      else
        puts "  ✗ No repository contents found"
      end
    rescue Octokit::NotFound
      puts "  ✗ Repository not found or inaccessible"
    rescue => e
      puts "  ✗ Error fetching repository structure: #{e.message}"
      
      # Fallback: try to get basic file info from languages
      if repo_info[:languages] && repo_info[:languages].any?
        # Estimate file types from languages
        repo_info[:file_types] = estimate_file_types_from_languages(repo_info[:languages])
        puts "  ✓ File types estimated from languages"
      end
    end

    # Check for important files
    repo_info[:important_files] = check_important_files(repo)

    # Get pull requests stats
    begin
      prs = @client.pull_requests(repo.full_name, state: 'all', per_page: 100)
      if prs
        repo_info[:total_pull_requests] = prs.length
        repo_info[:merged_pull_requests] = prs.count { |pr| pr.merged_at }
        puts "  ✓ Pull requests analyzed"
      end
    rescue => e
      puts "  ✗ Error fetching PRs: #{e.message}"
    end

    # Get issues stats
    begin
      issues = @client.issues(repo.full_name, state: 'all', per_page: 100)
      if issues
        # Filter out pull requests from issues
        actual_issues = issues.reject { |i| i.respond_to?(:pull_request) && i.pull_request }
        repo_info[:total_issues] = actual_issues.length
        repo_info[:closed_issues] = actual_issues.count { |i| i.state == 'closed' }
        puts "  ✓ Issues analyzed"
      end
    rescue => e
      puts "  ✗ Error fetching issues: #{e.message}"
    end

    # Save repository info
    save_data(repo_dir, 'repo_info.json', repo_info)

    repo_info
  end

  def save_user_profile(user)
    profile = {
      login: user.login,
      name: user.name,
      bio: user.bio,
      company: user.company,
      location: user.location,
      email: user.email,
      blog: user.blog,
      twitter_username: user.respond_to?(:twitter_username) ? user.twitter_username : nil,
      hireable: user.hireable,
      public_repos: user.public_repos,
      public_gists: user.public_gists,
      followers: user.followers,
      following: user.following,
      created_at: user.created_at,
      updated_at: user.updated_at
    }

    save_data(@output_dir, 'user_profile.json', profile)
  end

  def calculate_language_percentages(languages)
    return {} if languages.nil? || languages.empty?

    total = languages.values.sum.to_f
    return {} if total == 0

    languages.transform_values { |bytes| ((bytes / total) * 100).round(2) }
  end

  def analyze_commit_frequency(commit_dates)
    return {} if commit_dates.empty?

    # Group commits by month
    monthly_commits = commit_dates.group_by { |date| date.strftime('%Y-%m') }

    {
      commits_per_month: monthly_commits.transform_values(&:count),
      average_commits_per_month: (commit_dates.length.to_f / monthly_commits.keys.length).round(2),
      most_active_month: monthly_commits.max_by { |_, commits| commits.length }&.first
    }
  end

  def format_tree_structure(tree_items)
    tree_hash = {}

    tree_items.each do |item|
      path_parts = item.path.split('/')
      current = tree_hash

      path_parts.each_with_index do |part, i|
        if i == path_parts.length - 1
          current[part] = item.type
        else
          current[part] ||= {}
          current = current[part]
        end
      end
    end

    format_tree_hash(tree_hash)
  end

  def format_tree_hash(hash, prefix = "", is_last = true)
    output = ""
    items = hash.to_a

    items.each_with_index do |(key, value), index|
      is_last_item = index == items.length - 1

      if value.is_a?(Hash)
        output += "#{prefix}#{is_last_item ? '└── ' : '├── '}#{key}/\n"
        extension = is_last_item ? "    " : "│   "
        output += format_tree_hash(value, prefix + extension, is_last_item)
      else
        output += "#{prefix}#{is_last_item ? '└── ' : '├── '}#{key}\n"
      end
    end

    output
  end

  def analyze_file_types(tree_items)
    extensions = tree_items
      .select { |item| item.type == 'blob' }
      .map { |item| File.extname(item.path).downcase }
      .reject(&:empty?)

    extensions.tally.sort_by { |_, count| -count }.to_h
  end

  def check_important_files(repo)
    important_files = {
      'README.md' => false,
      'LICENSE' => false,
      'CONTRIBUTING.md' => false,
      'CODE_OF_CONDUCT.md' => false,
      '.github/workflows' => false,
      'package.json' => false,
      'Gemfile' => false,
      'requirements.txt' => false,
      'Dockerfile' => false,
      '.travis.yml' => false,
      '.github/actions' => false,
      'documentation' => false
    }

    begin
      # Check root contents
      contents = @client.contents(repo.full_name)
      contents.each do |item|
        important_files.keys.each do |file|
          if item.path.downcase.include?(file.downcase)
            important_files[file] = true
          end
        end
      end
    rescue => e
      # Ignore errors
    end

    important_files.select { |_, exists| exists }.keys
  end

  def update_skills_summary(summary, repo_info)
    # Update language statistics
    if repo_info[:languages]
      repo_info[:languages].each do |lang, bytes|
        summary[:languages][lang] ||= 0
        summary[:languages][lang] += bytes
      end
    end

    # Update topics
    if repo_info[:topics]
      repo_info[:topics].each do |topic|
        summary[:topics][topic] ||= 0
        summary[:topics][topic] += 1
      end
    end

    # Update totals
    summary[:total_stars] += repo_info[:stars] || 0
    summary[:total_forks] += repo_info[:forks] || 0
    summary[:total_contributions] += repo_info[:user_contributions] || 0
  end

  def generate_resume_insights(summary)
    insights = {
      generated_at: DateTime.now.iso8601,

      # Key metrics
      total_stars_earned: summary[:skills_summary][:total_stars],
      total_forks: summary[:skills_summary][:total_forks],
      total_contributions: summary[:skills_summary][:total_contributions],

      # Career timeline
      career_span: calculate_career_span(summary[:repositories]),
      coding_activity: analyze_coding_activity(summary[:repositories]),

      # Language expertise with experience indicators
      primary_languages: enhance_language_analysis(summary[:skills_summary][:languages], summary[:repositories]),

      # Technology expertise detection
      technology_stack: detect_technology_stack(summary[:repositories]),
      
      # Traditional expertise areas from topics
      expertise_areas: summary[:skills_summary][:topics]
        .sort_by { |_, count| -count }
        .first(10)
        .to_h,

      # Professional indicators
      professional_indicators: analyze_professional_indicators(summary[:repositories]),

      # Repository highlights
      most_starred_repos: summary[:repositories]
        .sort_by { |r| -(r[:stars] || 0) }
        .first(5)
        .map { |r| { name: r[:name], stars: r[:stars], description: r[:description] } },

      most_contributed_repos: summary[:repositories]
        .sort_by { |r| -(r[:user_contributions] || 0) }
        .first(5)
        .map { |r| { name: r[:name], contributions: r[:user_contributions], role: r[:is_fork] ? 'Contributor' : 'Owner' } },

      # Active projects
      recently_updated: summary[:repositories]
        .sort_by { |r| r[:pushed_at] || '' }
        .reverse
        .first(5)
        .map { |r| { name: r[:name], last_updated: r[:pushed_at], description: r[:description] } },

      # Open source contributions
      contributed_to_external: summary[:repositories]
        .select { |r| r[:is_fork] }
        .map { |r| { name: r[:name], contributions: r[:user_contributions] } },

      # Project diversity
      project_types: {
        web_apps: summary[:repositories].count { |r| r[:topics]&.any? { |t| ['web', 'webapp', 'frontend', 'backend'].include?(t) } },
        libraries: summary[:repositories].count { |r| r[:topics]&.any? { |t| ['library', 'framework', 'package'].include?(t) } },
        tools: summary[:repositories].count { |r| r[:topics]&.any? { |t| ['cli', 'tool', 'utility'].include?(t) } },
        data_science: summary[:repositories].count { |r| r[:topics]&.any? { |t| ['data-science', 'machine-learning', 'ai', 'ml'].include?(t) } },
        mobile: summary[:repositories].count { |r| r[:topics]&.any? { |t| ['mobile', 'ios', 'android', 'react-native'].include?(t) } }
      },

      # Documentation quality
      well_documented_projects: summary[:repositories]
        .select { |r| r[:has_readme] && r[:important_files]&.include?('LICENSE') }
        .count,

      # Collaboration metrics
      projects_with_contributors: summary[:repositories]
        .select { |r| (r[:total_contributors] || 0) > 1 }
        .count,

      # Release management
      projects_with_releases: summary[:repositories]
        .select { |r| (r[:total_releases] || 0) > 0 }
        .count
    }

    # Save insights
    save_data(@output_dir, 'resume_insights.json', insights)

    # Generate a skills summary for easy consumption
    skills_summary = generate_skills_summary(insights)
    save_data(@output_dir, 'skills_summary.json', skills_summary)

    # Generate a markdown resume snippet
    resume_md = generate_resume_markdown(summary, insights)
    save_data(@output_dir, 'resume_snippet.md', resume_md)
  end

  def generate_resume_markdown(summary, insights)
    md = "# GitHub Portfolio Summary\n\n"
    md += "**Generated:** #{DateTime.now.strftime('%B %d, %Y')}\n\n"

    # Professional Summary
    md += "## Professional Summary\n"
    md += "- **Total Repositories:** #{summary[:total_repos]}\n"
    md += "- **Total Stars Earned:** #{insights[:total_stars_earned]}\n"
    md += "- **Total Contributions:** #{insights[:total_contributions]}\n"
    md += "- **Years Active:** #{insights[:career_span][:years_active]}\n" if insights[:career_span][:years_active]
    md += "- **Consistency Score:** #{insights[:coding_activity][:consistency_score]}%\n" if insights[:coding_activity][:consistency_score]
    md += "- **Member Since:** #{Date.parse(summary[:user][:created_at].to_s).strftime('%B %Y')}\n\n"

    # Technical Skills - Enhanced
    md += "## Technical Skills\n\n"
    md += "### Programming Languages\n"
    if insights[:primary_languages].any?
      insights[:primary_languages].each do |lang, stats|
        md += "- **#{lang}** - #{stats[:experience_level]} (#{stats[:project_count]} projects)\n"
      end
    end

    # Technology Stack
    if insights[:technology_stack] && insights[:technology_stack].any?
      insights[:technology_stack].each do |category, techs|
        next if techs.empty?
        
        md += "\n### #{category.to_s.split('_').map(&:capitalize).join(' ')}\n"
        techs.each do |tech, details|
          md += "- **#{tech}** (#{details[:project_count]} projects)\n"
        end
      end
    end

    # Professional Indicators
    if insights[:professional_indicators]
      md += "\n## Professional Development\n"
      prof = insights[:professional_indicators]
      
      md += "- **Documentation Quality:** #{prof[:documentation_quality]}%\n"
      md += "- **Testing Practices:** #{prof[:testing_practices][:testing_percentage]}%\n"
      md += "- **Project Organization:** #{prof[:project_organization][:organization_score]}%\n"
      md += "- **Collaboration Experience:** #{prof[:collaboration_experience][:collaborative_projects]} projects\n"
      md += "- **Active Maintenance:** #{prof[:maintenance_commitment][:maintenance_percentage]}%\n\n"
    end

    # Notable Projects
    if insights[:most_starred_repos].any?
      md += "## Notable Projects\n\n"
      insights[:most_starred_repos].each do |repo|
        md += "### #{repo[:name]}\n"
        md += "#{repo[:description]}\n" if repo[:description]
        md += "- ⭐ #{repo[:stars]} stars\n\n"
      end
    end

    # Activity and Contributions
    md += "## Development Activity\n"
    if insights[:coding_activity]
      activity = insights[:coding_activity]
      md += "- **Active Projects:** #{activity[:total_active_projects]}\n"
      md += "- **Long-term Projects:** #{activity[:long_term_projects]} (12+ months)\n"
      md += "- **Avg Commits/Project:** #{activity[:average_commits_per_project].round(1)}\n"
    end

    # Open Source Contributions
    md += "\n## Open Source Contributions\n"
    if insights[:contributed_to_external].any?
      insights[:contributed_to_external].each do |contrib|
        md += "- **#{contrib[:name]}**: #{contrib[:contributions]} contributions\n"
      end
    else
      md += "- Primarily focused on personal projects\n"
    end

    # Architectural Patterns
    if insights[:technology_stack] && insights[:technology_stack][:architectural_patterns] && insights[:technology_stack][:architectural_patterns].any?
      md += "\n## Architectural Experience\n"
      insights[:technology_stack][:architectural_patterns].each do |pattern|
        md += "- #{pattern}\n"
      end
    end

    md
  end

  def generate_skills_summary(insights)
    {
      technical_skills: {
        programming_languages: insights[:primary_languages]&.keys || [],
        frameworks: insights[:technology_stack]&.dig(:frameworks)&.keys || [],
        databases: insights[:technology_stack]&.dig(:databases)&.keys || [],
        cloud_platforms: insights[:technology_stack]&.dig(:cloud_platforms)&.keys || [],
        tools_and_practices: insights[:technology_stack]&.dig(:tools_and_practices)&.keys || []
      },
      experience_metrics: {
        years_active: insights[:career_span]&.dig(:years_active) || 0,
        total_projects: insights[:coding_activity]&.dig(:total_active_projects) || 0,
        consistency_score: insights[:coding_activity]&.dig(:consistency_score) || 0,
        stars_earned: insights[:total_stars_earned] || 0
      },
      professional_indicators: {
        documentation_quality: insights[:professional_indicators]&.dig(:documentation_quality) || 0,
        testing_practices: insights[:professional_indicators]&.dig(:testing_practices, :testing_percentage) || 0,
        collaboration_experience: insights[:professional_indicators]&.dig(:collaboration_experience, :collaborative_projects) || 0,
        maintenance_commitment: insights[:professional_indicators]&.dig(:maintenance_commitment, :maintenance_percentage) || 0
      },
      architectural_patterns: insights[:technology_stack]&.dig(:architectural_patterns) || [],
      top_repositories: insights[:most_starred_repos]&.map { |r| r[:name] } || []
    }
  end

  def calculate_career_span(repositories)
    dates = repositories.flat_map do |repo|
      [repo[:created_at], repo[:first_commit], repo[:last_commit]].compact
    end.map { |d| Date.parse(d.to_s) rescue nil }.compact
    
    return {} if dates.empty?
    
    earliest = dates.min
    latest = dates.max
    
    {
      start_date: earliest.strftime('%Y-%m'),
      latest_activity: latest.strftime('%Y-%m'),
      years_active: ((latest - earliest) / 365.25).round(1),
      total_active_years: dates.group_by(&:year).keys.length
    }
  end

  def analyze_coding_activity(repositories)
    # Analyze commit patterns and project consistency
    active_repos = repositories.select { |r| r[:total_commits] && r[:total_commits] > 0 }
    
    {
      total_active_projects: active_repos.length,
      average_commits_per_project: active_repos.map { |r| r[:total_commits] || 0 }.sum.to_f / [active_repos.length, 1].max,
      projects_with_regular_commits: active_repos.count { |r| (r[:total_commits] || 0) >= 10 },
      long_term_projects: active_repos.count { |r| project_duration_months(r) >= 12 },
      consistency_score: calculate_consistency_score(repositories)
    }
  end

  def project_duration_months(repo)
    return 0 unless repo[:first_commit] && repo[:last_commit]
    
    start_date = Date.parse(repo[:first_commit].to_s) rescue nil
    end_date = Date.parse(repo[:last_commit].to_s) rescue nil
    
    return 0 unless start_date && end_date
    
    ((end_date - start_date) / 30.44).round # Average days per month
  end

  def calculate_consistency_score(repositories)
    # Score based on regular activity, documentation, and maintenance
    total_score = 0
    max_score = 0
    
    repositories.each do |repo|
      score = 0
      possible = 0
      
      # Documentation score
      if repo[:has_readme]
        score += 2
      end
      possible += 2
      
      # Maintenance score
      if repo[:important_files]&.any?
        score += 1
      end
      possible += 1
      
      # Activity score
      if (repo[:total_commits] || 0) >= 5
        score += 2
      elsif (repo[:total_commits] || 0) >= 1
        score += 1
      end
      possible += 2
      
      # Collaboration score
      if (repo[:total_contributors] || 0) > 1
        score += 1
      end
      possible += 1
      
      total_score += score
      max_score += possible
    end
    
    max_score > 0 ? (total_score.to_f / max_score * 100).round(1) : 0
  end

  def enhance_language_analysis(languages, repositories)
    return {} if languages.empty?
    
    # Calculate not just bytes but also project count and recency
    language_stats = {}
    
    languages.sort_by { |_, bytes| -bytes }.first(8).each do |lang, bytes|
      projects_with_lang = repositories.count { |r| r[:language] == lang || r[:languages]&.key?(lang) }
      
      # Find most recent project with this language
      recent_projects = repositories
        .select { |r| r[:language] == lang || r[:languages]&.key?(lang) }
        .sort_by { |r| r[:pushed_at] || '' }
        .reverse
      
      language_stats[lang] = {
        total_bytes: bytes,
        project_count: projects_with_lang,
        most_recent_use: recent_projects.first&.dig(:pushed_at),
        experience_level: determine_experience_level(bytes, projects_with_lang)
      }
    end
    
    language_stats
  end

  def determine_experience_level(bytes, project_count)
    if project_count >= 5 && bytes >= 100000
      'Expert'
    elsif project_count >= 3 && bytes >= 50000
      'Proficient'
    elsif project_count >= 2 || bytes >= 20000
      'Intermediate'
    else
      'Familiar'
    end
  end

  def detect_technology_stack(repositories)
    tech_indicators = {
      frameworks: detect_frameworks(repositories),
      databases: detect_databases(repositories),
      cloud_platforms: detect_cloud_platforms(repositories),
      tools_and_practices: detect_tools_and_practices(repositories),
      architectural_patterns: detect_architectural_patterns(repositories)
    }
    
    tech_indicators.reject { |_, v| v.empty? }
  end

  def detect_frameworks(repositories)
    framework_patterns = {
      'React' => ['react', 'jsx', 'create-react-app'],
      'Vue.js' => ['vue', 'nuxt'],
      'Angular' => ['angular', '@angular'],
      'Express.js' => ['express', 'expressjs'],
      'Django' => ['django', 'requirements.txt'],
      'Rails' => ['rails', 'gemfile'],
      'Spring' => ['spring', 'maven', 'gradle'],
      'Flask' => ['flask'],
      'FastAPI' => ['fastapi'],
      'Next.js' => ['next', 'nextjs'],
      'Svelte' => ['svelte'],
      'Laravel' => ['laravel', 'composer.json']
    }
    
    detect_tech_from_patterns(repositories, framework_patterns)
  end

  def detect_databases(repositories)
    db_patterns = {
      'MongoDB' => ['mongodb', 'mongoose'],
      'PostgreSQL' => ['postgresql', 'postgres', 'pg'],
      'MySQL' => ['mysql'],
      'Redis' => ['redis'],
      'SQLite' => ['sqlite'],
      'Elasticsearch' => ['elasticsearch', 'elastic'],
      'Firebase' => ['firebase']
    }
    
    detect_tech_from_patterns(repositories, db_patterns)
  end

  def detect_cloud_platforms(repositories)
    cloud_patterns = {
      'AWS' => ['aws', 'amazon', 's3', 'ec2', 'lambda'],
      'Google Cloud' => ['gcp', 'google-cloud', 'firebase'],
      'Azure' => ['azure', 'microsoft'],
      'Heroku' => ['heroku'],
      'Vercel' => ['vercel'],
      'Netlify' => ['netlify'],
      'DigitalOcean' => ['digitalocean']
    }
    
    detect_tech_from_patterns(repositories, cloud_patterns)
  end

  def detect_tools_and_practices(repositories)
    tools_patterns = {
      'Docker' => ['docker', 'dockerfile'],
      'Kubernetes' => ['kubernetes', 'k8s'],
      'CI/CD' => ['github/workflows', '.travis.yml', 'jenkins', 'gitlab-ci'],
      'Testing' => ['test', 'spec', 'jest', 'pytest', 'rspec'],
      'TypeScript' => ['typescript', '.ts'],
      'GraphQL' => ['graphql'],
      'REST API' => ['api', 'rest', 'endpoint'],
      'Microservices' => ['microservice', 'service'],
      'WebSocket' => ['websocket', 'socket.io']
    }
    
    detect_tech_from_patterns(repositories, tools_patterns)
  end

  def detect_architectural_patterns(repositories)
    patterns = {
      'Monorepo' => repositories.any? { |r| r[:file_types]&.key?('.json') && r[:total_directories] && r[:total_directories] > 10 },
      'Microservices' => repositories.count { |r| r[:name]&.include?('service') || r[:description]&.include?('microservice') } >= 2,
      'API-First' => repositories.count { |r| r[:name]&.include?('api') || r[:description]&.match?(/api|rest|graphql/i) } >= 2,
      'Full-Stack' => has_frontend_and_backend?(repositories),
      'Mobile Development' => repositories.any? { |r| r[:topics]&.any? { |t| ['mobile', 'ios', 'android', 'react-native', 'flutter'].include?(t) } }
    }
    
    patterns.select { |_, detected| detected }.keys
  end

  def has_frontend_and_backend?(repositories)
    frontend_langs = ['JavaScript', 'TypeScript', 'HTML', 'CSS', 'Vue', 'React']
    backend_langs = ['Python', 'Ruby', 'Java', 'Go', 'C#', 'PHP', 'Node.js']
    
    has_frontend = repositories.any? { |r| frontend_langs.include?(r[:language]) }
    has_backend = repositories.any? { |r| backend_langs.include?(r[:language]) || r[:languages]&.keys&.any? { |l| backend_langs.include?(l) } }
    
    has_frontend && has_backend
  end

  def detect_tech_from_patterns(repositories, patterns)
    detected = {}
    
    patterns.each do |tech, keywords|
      matches = repositories.select do |repo|
        keywords.any? do |keyword|
          [repo[:name], repo[:description], repo[:topics], repo[:important_files]].flatten.compact.any? do |field|
            field.to_s.downcase.include?(keyword.downcase)
          end
        end
      end
      
      if matches.any?
        detected[tech] = {
          project_count: matches.length,
          projects: matches.map { |r| r[:name] }.first(3)
        }
      end
    end
    
    detected
  end

  def analyze_professional_indicators(repositories)
    indicators = {
      documentation_quality: calculate_documentation_score(repositories),
      testing_practices: analyze_testing_practices(repositories),
      project_organization: analyze_project_organization(repositories),
      collaboration_experience: analyze_collaboration(repositories),
      maintenance_commitment: analyze_maintenance(repositories)
    }
    
    indicators
  end

  def calculate_documentation_score(repositories)
    total_repos = repositories.length
    return 0 if total_repos == 0
    
    documented_repos = repositories.count do |repo|
      repo[:has_readme] && repo[:readme_size] && repo[:readme_size] > 500
    end
    
    (documented_repos.to_f / total_repos * 100).round(1)
  end

  def analyze_testing_practices(repositories)
    test_indicators = ['test', 'spec', '.test.', '_test.', 'jest', 'pytest', 'rspec', 'mocha']
    
    repos_with_tests = repositories.count do |repo|
      repo[:file_types]&.any? { |ext, _| test_indicators.any? { |indicator| ext.include?(indicator) } } ||
        repo[:important_files]&.any? { |file| test_indicators.any? { |indicator| file.downcase.include?(indicator) } }
    end
    
    {
      repos_with_tests: repos_with_tests,
      testing_percentage: repositories.length > 0 ? (repos_with_tests.to_f / repositories.length * 100).round(1) : 0
    }
  end

  def analyze_project_organization(repositories)
    well_organized = repositories.count do |repo|
      has_license = repo[:license]
      has_structure = repo[:total_directories] && repo[:total_directories] >= 3
      has_documentation = repo[:has_readme]
      
      [has_license, has_structure, has_documentation].count(true) >= 2
    end
    
    {
      well_organized_projects: well_organized,
      organization_score: repositories.length > 0 ? (well_organized.to_f / repositories.length * 100).round(1) : 0
    }
  end

  def analyze_collaboration(repositories)
    collaborative_repos = repositories.select { |r| (r[:total_contributors] || 0) > 1 }
    
    {
      collaborative_projects: collaborative_repos.length,
      total_external_contributors: collaborative_repos.sum { |r| (r[:total_contributors] || 1) - 1 },
      projects_with_prs: repositories.count { |r| (r[:total_pull_requests] || 0) > 0 },
      average_contributors_per_project: repositories.length > 0 ? (repositories.sum { |r| r[:total_contributors] || 1 }.to_f / repositories.length).round(1) : 0
    }
  end

  def analyze_maintenance(repositories)
    recently_maintained = repositories.count do |repo|
      last_push = repo[:pushed_at]
      next false unless last_push
      
      Date.parse(last_push.to_s) >= Date.today - 365 rescue false
    end
    
    {
      recently_maintained_projects: recently_maintained,
      maintenance_percentage: repositories.length > 0 ? (recently_maintained.to_f / repositories.length * 100).round(1) : 0,
      projects_with_releases: repositories.count { |r| (r[:total_releases] || 0) > 0 }
    }
  end

  def estimate_file_types_from_languages(languages)
    language_to_extension = {
      'JavaScript' => '.js',
      'TypeScript' => '.ts',
      'Python' => '.py',
      'Ruby' => '.rb',
      'Java' => '.java',
      'C++' => '.cpp',
      'C' => '.c',
      'C#' => '.cs',
      'Go' => '.go',
      'Rust' => '.rs',
      'PHP' => '.php',
      'Swift' => '.swift',
      'Kotlin' => '.kt',
      'Scala' => '.scala',
      'HTML' => '.html',
      'CSS' => '.css',
      'SCSS' => '.scss',
      'Vue' => '.vue',
      'CoffeeScript' => '.coffee',
      'Shell' => '.sh',
      'PowerShell' => '.ps1',
      'Dockerfile' => '',
      'YAML' => '.yml',
      'JSON' => '.json',
      'XML' => '.xml',
      'Markdown' => '.md'
    }
    
    estimated_types = {}
    
    languages.each do |lang, bytes|
      extension = language_to_extension[lang]
      if extension && !extension.empty?
        estimated_types[extension] = (bytes / 1000).round # Rough estimate of file count
      end
    end
    
    estimated_types
  end

  def save_data(dir, filename, data, binary: false)
    path = File.join(dir, filename)
    if data.is_a?(String)
      File.write(path, data, mode: binary ? 'wb' : 'w')
    else
      File.write(path, JSON.pretty_generate(data))
    end
  end
end

# Parse command line options
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: ruby github_resume_scanner.rb [options]"

  opts.on("-l", "--limit N", Integer, "Limit number of repositories to scan") do |n|
    options[:limit] = n
  end

  opts.on("-s", "--skip-forks", "Skip forked repositories") do
    options[:skip_forks] = true
  end

  opts.on("-a", "--skip-archived", "Skip archived repositories") do
    options[:skip_archived] = true
  end

  opts.on("-L", "--language LANG", "Filter by programming language") do |lang|
    options[:filter_language] = lang
  end

  opts.on("-m", "--min-stars N", Integer, "Minimum stars required") do |n|
    options[:min_stars] = n
  end

  opts.on("-o", "--output DIR", "Output directory") do |dir|
    options[:output_dir] = dir
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Main execution
if __FILE__ == $0
  token = ENV['GITHUB_TOKEN']

  unless token
    puts "Please set your GitHub token:"
    puts "1. Go to https://github.com/settings/tokens"
    puts "2. Generate a new token with 'repo' scope"
    puts "3. Run: export GITHUB_TOKEN='your_token'"
    exit 1
  end

  scanner = GitHubResumeScanner.new(token, options)
  scanner.scan_all_repos
end
