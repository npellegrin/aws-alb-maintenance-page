# AWS ALB Maintenance Page

This is a lightweight Bash script to enable/disable maintenance page on an AWS Application Load Balancer (ALB) using fixed responses.

## Overview

This script allows you to quickly show a maintenance page on your ALB by creating ALB rules with fixed responses. The script:

- Creates ALB rules with fixed responses for HTML/CSS content
- Validates payload sizes (limited to 1024 bytes by ALB)
- Supports two modes: `maintenance` and `sleep`
- Provides clear error messages and validation

## Prerequisites

- **AWS CLI** installed and configured (`aws configure`)
- **Bash 4.0+** (for associative arrays and `set -Eeuo pipefail`)
- AWS permissions to:
  - Describe ALB rules
  - Create/delete ALB rules

## Required IAM Permissions

### Policy example

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:CreateRule",
                "elasticloadbalancing:DeleteRule"
            ],
            "Resource": [
                "arn:aws:elasticloadbalancing:{{REGION}}:{{ACCOUNT_ID}}:listener/app/{{ALB_NAME}}/{{LISTENER_ID}}",
                "arn:aws:elasticloadbalancing:{{REGION}}:{{ACCOUNT_ID}}:listener-rule/app/{{ALB_NAME}}/{{LISTENER_ID}}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:DescribeRules",
            ],
            "Resource": "*"
        }
    ]
}
```

### Important Note on ARNs

- **listener** (e.g., arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/my-alb/1234567890abcdef) is required for **CreateRule**.
- **listener-rule** (e.g., arn:aws:elasticloadbalancing:us-east-1:123456789012:listener-rule/app/my-alb/1234567890abcdef/*) is required for **DeleteRule**.

**These are distinct resources**.

## Installation

1. Clone or download this repository:

```bash
git clone git@github.com:npellegrin/aws-alb-maintenance-page.git
cd alb-maintenance-page
```

Configure your ALB listener ARN and AWS region by editing the top of alb.sh:

```bash
readonly LISTENER_ARN="arn:aws:elasticloadbalancing:eu-west-1:123456789012:listener/app/your-alb/1234567890abcdef/1234567890abcdef"
readonly AWS_REGION="eu-west-1"
```

## Usage

### Enable Maintenance Mode

```bash
./alb.sh maintenance on
```

This will:

- Create two ALB rules (priority 1 for CSS, priority 2 for HTML)
- Return HTTP 503 for all requests (/*)
- Serve your maintenance.html and maintenance.css files

### Enable Sleep Mode

```bash
./alb.sh sleep on
```

This will:

- Create two ALB rules (priority 1 for CSS, priority 2 for HTML)
- Return HTTP 503 for all requests (/*)
- Serve your sleep.html and sleep.css files

### Disable Mode

```bash
./alb.sh maintenance off
# or
./alb.sh sleep off
```

This will remove the ALB rules and restore normal traffic flow.

### Help

```bash
./alb.sh --help
```

## Modifying the Script

### Adding a New Mode

1. Create new HTML/CSS files in the html/ and css/ directories
2. Add the new mode to the parse_arguments() function:

```bash
    [[ $MODE == "maintenance" || $MODE == "sleep" ||  $ MODE == "newmode" ]] || \
        fail "Invalid mode ' $ MODE'."
```

### Changing Default Priorities

Edit these variables at the top of the script:

```bash
readonly BASE_RULE_PRIORITY=1
```

## License: GNU General Public License v3.0

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
License Implications
