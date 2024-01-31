# PR Reviewer

PR Reviewer is a Ruby script that analyzes a pull request and generates comments for the pull request using the OpenAI API. By default, it uses OpenAI's `gpt-4` model.

## Prerequisites

Before you begin, ensure you have met the following requirements:

* You have Ruby installed.
* You have a GitHub TOKEN.
* You have an OpenAI API KEY.

## Installing PR Reviewer

To install PR Reviewer, follow these steps:

1. Clone the repository
2. Install the required gems with `bundle install`

## Using PR Reviewer

To use PR Reviewer, follow these steps:

1. Set your GitHub token and OpenAI API key as environment variables:

    ```bash
    export GITHUB_TOKEN=your_github_token
    export OPENAI_API_KEY=your_openai_api_key
    export OPENAI_API_MODEL=your_preferred_open_ai_mode #Optional
    ```

2. Run the script with the repository and pull request number as arguments:

    ```bash
    ruby pr_reviewer.rb <owner>/<repo> <pr_number>
    ```

## Acknowledgements

This script is inspired by the [AI CodeReviewer](https://github.com/freeedcom/ai-codereviewer) project.

