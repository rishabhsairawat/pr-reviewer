# frozen_string_literal: true

require 'octokit'
require 'json'
require 'git_diff'
require 'openai'

##
# PRAgent is a class that analyzes a pull request and generates comments for the pull request.
# It uses the OpenAI API to generate comments.
# It takes the following arguments:
# - repo: The repository name in the format <owner>/<repo>, e.g. 'rishabhsairawat/pr-reviewer'
# - pr_number: The pull request number, e.g. 1
# Usage: ruby pr_reviewer.rb <owner>/<repo> <pr_number>
# Example: ruby pr_reviewer.rb rishabhsairawat/pr-reviewer 1
class PRAgent
  # Initializes a new instance of the PRAgent class.
  #
  # @param repo [String] the name of the repository
  # @param pr_number [Integer] the number of the pull request
  def initialize(repo, pr_number)
    github_token = ENV['GITHUB_TOKEN'] || raise('GITHUB_TOKEN is not provided')
    openai_key = ENV['OPENAI_API_KEY'] || raise('OPENAI_API_KEY is not provided')
    Octokit.configure do |c|
      c.access_token = github_token
    end

    @client = Octokit::Client.new
    @openai = OpenAI::Client.new(access_token: openai_key)
    @repo = repo
    @pr_number = pr_number
    @logger = Logger.new($stdout)
  end

  # Reviews the pull request by fetching details, analyzing the diff, generating comments, and pushing them to GitHub.
  def review_pr
    pr_details = fetch_pr_details
    diff = fetch_diff(pr_details[:owner], pr_details[:repo], pr_details[:pull_number])
    comments = analyze_diff_and_generate_comments(diff, pr_details)
    push_comments_to_github(comments)
  end

  private

  # Fetches the details of a pull request.
  #
  # @return [Hash] The details of the pull request, including owner, repo, pull_number, title, and description.
  def fetch_pr_details
    @logger.debug("Fetching PR details for #{@repo}##{@pr_number}")
    pr_response = @client.pull_request(@repo, @pr_number)
    repository = pr_response[:head][:repo]
    {
      owner: repository[:owner][:login],
      repo: repository[:name],
      pull_number: @pr_number,
      title: pr_response[:title],
      description: pr_response[:body]
    }
  end

  # Fetches the diff for a specific pull request.
  #
  # @param owner [String] the owner of the repository
  # @param repo [String] the name of the repository
  # @param pull_number [Integer] the number of the pull request
  # @return [String] the diff content of the pull request
  def fetch_diff(owner, repo, pull_number)
    @logger.debug("Fetching diff for https://github.com/#{owner}/#{repo}/pull/#{pull_number}")
    @client.pull_request("#{owner}/#{repo}", pull_number, accept: 'application/vnd.github.diff')
  end

  # Analyzes the diff and generates comments based on the changes made in the pull request.
  #
  # Parameters:
  # - diff: A string representing the diff of the pull request.
  # - pr_details: A hash containing details of the pull request.
  #
  # Returns:
  # An array of comments generated based on the diff.
  def analyze_diff_and_generate_comments(diff, pr_details)
    @logger.debug('Analyzing diff and generating comments')
    diff = GitDiff.from_string(diff)
    comments = []
    diff.files.each do |file|
      next if file.b_path == '/dev/null'

      changes = file.hunks.map do |hunk|
        [hunk.lines.map do |line|
           "#{line.line_number.right} #{line.content}"
         end]
      end.join("\n")
      prompt = create_prompt(file, pr_details, changes)
      ai_response = get_ai_response(prompt)
      comments += create_comments(file, ai_response)
    end
    comments
  end

  # Creates a prompt for the AI model based on the file, pull request details, and changes.
  #
  # @param file [GitDiff::File] the file being reviewed
  # @param pr_details [Hash] the details of the pull request
  # @param changes [String] the changes made in the pull request
  # @return [String] the prompt for the AI model
  def create_prompt(file, pr_details, changes)
    "Your task is to review pull requests. Instructions:
    - Provide the response in following JSON format:  {\"reviews\": [{\"lineNumber\":  <line_number>, \"reviewComment\": \"<review comment>\"}]}
    - Do not give positive comments or compliments.
    - Provide comments and suggestions ONLY if there is something to improve, otherwise \"reviews\" should be an empty array.
    - Write the comment in GitHub Markdown format.
    - Provide comments only for the lines that have been changed. Changes are marked with a + or - sign at the beginning of the line.
    - Do not provide comments for the files which only have documentation or formatting changes.
    - Use the given description only for the overall context and only comment the code.
    - Don't comment on the same line more than once. If multiple comments are needed, combine them into one comment.
    - Don't provide comments for .json, .yml, or .xml type files.
    - Don't comment for adding a newline at the end of the file
    - IMPORTANT: NEVER suggest adding comments/documention to the code.

    Review the following code diff in the file \"#{file.b_path}\" and take the pull request title and description into account when writing the response.

    Pull request title: #{pr_details[:title]}
    Pull request description:

    ---
    #{pr_details[:description]}
    ---

    Git diff to review:

    \`\`\`dif
    #{changes}
    \`\`\`
    "
  end

  # Gets the AI model's response based on the prompt.
  #
  # @param prompt [String] the prompt for the AI model
  # @return [Hash] the AI model's response
  def get_ai_response(prompt)
    @openai.chat(parameters: {
                   model: ENV['OPENAI_API_MODEL'] || 'gpt-4',
                   messages: [{ role: 'system', content: prompt }],
                   temperature: 0.2
                 })
  rescue StandardError? => e
    @logger.error("Error while getting AI response: #{e.message}")
  end

  # Creates comments based on the AI model's response.
  #
  # @param file [GitDiff::File] the file being reviewed
  # @param ai_response [Hash] the AI model's response
  # @return [Array] the comments generated based on the AI model's response
  def create_comments(file, ai_response)
    comments = []
    if ai_response
      JSON.parse(ai_response['choices'][0]['message']['content'])['reviews'].each do |comment|
        comments << {
          path: file.b_path,
          line: comment['lineNumber'],
          body: comment['reviewComment']
        }
      end
    end
    comments
  end

  # Pushes the comments to GitHub.
  #
  # @param comments [Array] the comments to be pushed to GitHub
  def push_comments_to_github(comments)
    return if comments.empty?

    options = {
      event: 'COMMENT',
      comments: comments
    }
    begin
      @client.create_pull_request_review(@repo, @pr_number, options)
      @logger.info("Pushed #{comments.length} comments to GitHub")
    rescue StandardError? => e
      @logger.error("Error while pushing comments to GitHub: #{e.message}")
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  repo = ARGV[0]
  pr_number = ARGV[1].to_i
  pr_agent = PRAgent.new(repo, pr_number)
  pr_agent.review_pr
end
