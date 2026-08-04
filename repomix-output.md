This file is a merged representation of the entire codebase, combined into a single document by Repomix.

# File Summary

## Purpose
This file contains a packed representation of the entire repository's contents.
It is designed to be easily consumable by AI systems for analysis, code review,
or other automated processes.

## File Format
The content is organized as follows:
1. This summary section
2. Repository information
3. Directory structure
4. Multiple file entries, each consisting of:
  a. A header with the file path (## File: path/to/file)
  b. The full contents of the file in a code block

## Usage Guidelines
- This file should be treated as read-only. Any changes should be made to the
  original repository files, not this packed version.
- When processing this file, use the file path to distinguish
  between different files in the repository.
- Be aware that this file may contain sensitive information. Handle it with
  the same level of security as you would the original repository.

## Notes
- Some files may have been excluded based on .gitignore rules and Repomix's configuration
- Binary files are not included in this packed representation. Please refer to the Repository Structure section for a complete list of file paths, including binary files
- Files matching patterns in .gitignore are excluded
- Files matching default ignore patterns are excluded

## Additional Info

# Directory Structure
```
serverless-frontend/
  src/
    App.jsx
    main.jsx
  .gitignore
  .repomixignore
  eslint.config.js
  index.html
  package.json
  README.md
  vite.config.js
.gitignore
.repomixignore
index.html
lambda_function.py
main.tf
outputs.tf
provider.tf
```

# Files

## File: serverless-frontend/src/App.jsx
```javascript
import { useState, useEffect } from "react";
import {
  signIn,
  signUp,
  confirmSignUp,
  confirmSignIn,
  signOut,
  getCurrentUser,
  fetchAuthSession,
} from "aws-amplify/auth";
import { post } from "aws-amplify/api";
import "./App.css";

// View state machine:
//   "login" | "signup" | "verify" | "newPassword" | "app"
function App() {
  const [view, setView] = useState("login");

  // Shared fields
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

  // Sign-up specific
  const [confirmPassword, setConfirmPassword] = useState("");

  // Verify step
  const [code, setCode] = useState("");

  // New-password challenge
  const [newPassword, setNewPassword] = useState("");

  // App
  const [note, setNote] = useState("");
  const [status, setStatus] = useState("");

  const isError =
    status.toLowerCase().startsWith("error") ||
    status.toLowerCase().startsWith("failed");

  // Restore session on page load
  useEffect(() => {
    getCurrentUser()
      .then(() => setView("app"))
      .catch(() => {}); // no session — stay on login screen
  }, []);

  // ── 1. SIGN UP ──────────────────────────────────────────────
  const handleSignUp = async (e) => {
    e.preventDefault();
    if (password !== confirmPassword) {
      setStatus("Error: Passwords do not match.");
      return;
    }
    setStatus("Creating account...");
    try {
      const { nextStep } = await signUp({
        username: email,   // with username_attributes=["email"], email IS the username
        password,
        options: { userAttributes: { email } },
      });
      if (nextStep.signUpStep === "CONFIRM_SIGN_UP") {
        setStatus("Check your email for a verification code.");
        setView("verify");
      } else if (nextStep.signUpStep === "DONE") {
        // Auto-confirmed (e.g. admin confirmed users setting)
        setStatus("Account created! Please sign in.");
        setView("login");
      }
    } catch (err) {
      setPassword("");
      setConfirmPassword("");
      setStatus(`Error: ${err.message}`);
    }
  };

  // ── 2. CONFIRM SIGN UP (email code) ─────────────────────────
  const handleConfirmSignUp = async (e) => {
    e.preventDefault();
    setStatus("Verifying...");
    try {
      // username_attributes=["email"] means email is the username — use it directly
      await confirmSignUp({ username: email, confirmationCode: code });
      setStatus("Email verified! Please sign in.");
      setCode("");
      setView("login");
    } catch (err) {
      setCode("");
      setStatus(`Error: ${err.message}`);
    }
  };

  // ── 3. SIGN IN ───────────────────────────────────────────────
  const handleLogin = async (e) => {
    e.preventDefault();
    setStatus("Logging in...");
    try {
      const { nextStep } = await signIn({ username: email, password });

      if (
        nextStep.signInStep === "CONFIRM_SIGN_IN_WITH_NEW_PASSWORD_REQUIRED"
      ) {
        setView("newPassword");
        setStatus(
          "Admin password detected. Please set a new permanent password.",
        );
      } else if (nextStep.signInStep === "DONE") {
        setView("app");
        setStatus("Successfully logged in!");
      }
    } catch (err) {
      if (err.name === "UserAlreadyAuthenticatedException") {
        // Stale session — sign out and retry once
        try {
          await signOut();
          const { nextStep } = await signIn({ username: email, password });
          if (
            nextStep.signInStep ===
            "CONFIRM_SIGN_IN_WITH_NEW_PASSWORD_REQUIRED"
          ) {
            setView("newPassword");
            setStatus(
              "Admin password detected. Please set a new permanent password.",
            );
          } else if (nextStep.signInStep === "DONE") {
            setView("app");
            setStatus("Successfully logged in!");
          }
        } catch (retryErr) {
          setStatus(`Error: ${retryErr.message}`);
        }
      } else {
        setPassword("");
        setStatus(`Error: ${err.message}`);
      }
    }
  };

  // ── 4. NEW PASSWORD CHALLENGE ────────────────────────────────
  const handleNewPassword = async (e) => {
    e.preventDefault();
    try {
      const { nextStep } = await confirmSignIn({
        challengeResponse: newPassword,
      });
      if (nextStep.signInStep === "DONE") {
        setView("app");
        setNewPassword("");
        setStatus("Password updated and successfully logged in!");
      }
    } catch (err) {
      setNewPassword("");
      setStatus(`Error: ${err.message}`);
    }
  };

  // ── 5. SAVE NOTE ─────────────────────────────────────────────
  const handleSaveNote = async () => {
    if (!note.trim()) {
      setStatus("Error: Note cannot be empty.");
      return;
    }
    setStatus("Saving note...");
    try {
      const session = await fetchAuthSession();
      if (!session.tokens?.idToken) {
        setStatus("Error: Session expired. Please sign in again.");
        setView("login");
        return;
      }
      const token = session.tokens.idToken.toString();

      const restOperation = post({
        apiName: "NotesAPI",
        path: "/notes",
        options: {
          headers: { Authorization: token },
          body: { Note: note },
        },
      });

      const response = await restOperation.response;
      const data = await response.body.json();

      setStatus(`Note saved! ID: ${data.NoteId}`);
      setNote("");
    } catch (err) {
      console.error(err);
      setStatus(`Failed to save note: ${err.message}`);
    }
  };

  // ── 6. SIGN OUT ──────────────────────────────────────────────
  const handleSignOut = async () => {
    await signOut();
    setView("login");
    setEmail("");
    setPassword("");
    setNote("");
    setStatus("");
  };

  // ── RENDER ───────────────────────────────────────────────────
  return (
    <div className="app-shell">
      <div className="card">
        {/* Header */}
        <div className="card-header">
          <h1>Serverless Notes</h1>
          <p>Secured with AWS Cognito + API Gateway</p>
        </div>

        {/* Tab bar — only on login / signup views */}
        {(view === "login" || view === "signup") && (
          <div className="tab-bar">
            <button
              className={`tab${view === "login" ? " tab-active" : ""}`}
              onClick={() => { setView("login"); setStatus(""); }}
              type="button"
            >
              Sign in
            </button>
            <button
              className={`tab${view === "signup" ? " tab-active" : ""}`}
              onClick={() => { setView("signup"); setStatus(""); }}
              type="button"
            >
              Sign up
            </button>
          </div>
        )}

        {/* Sign in */}
        {view === "login" && (
          <form onSubmit={handleLogin}>
            <div className="form-group">
              <input
                className="input"
                type="email"
                placeholder="Email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
              />
              <input
                className="input"
                type="password"
                placeholder="Password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
              />
            </div>
            <div className="btn-row">
              <button className="btn btn-primary" type="submit">
                Sign in
              </button>
            </div>
          </form>
        )}

        {/* Sign up */}
        {view === "signup" && (
          <form onSubmit={handleSignUp}>
            <div className="form-group">
              <input
                className="input"
                type="email"
                placeholder="Email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
              />
              <input
                className="input"
                type="password"
                placeholder="Password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
              />
              <input
                className="input"
                type="password"
                placeholder="Confirm password"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                required
              />
            </div>
            <div className="btn-row">
              <button className="btn btn-primary" type="submit">
                Create account
              </button>
            </div>
          </form>
        )}

        {/* Email verification */}
        {view === "verify" && (
          <form onSubmit={handleConfirmSignUp}>
            <p className="form-title">Verify your email</p>
            <div className="form-group">
              <input
                className="input"
                type="text"
                placeholder="6-digit code"
                value={code}
                onChange={(e) => setCode(e.target.value)}
                maxLength={6}
                required
              />
            </div>
            <div className="btn-row">
              <button className="btn btn-primary" type="submit">
                Verify
              </button>
              <button
                className="btn btn-ghost"
                type="button"
                onClick={() => { setView("login"); setStatus(""); }}
              >
                Back
              </button>
            </div>
          </form>
        )}

        {/* New password challenge */}
        {view === "newPassword" && (
          <form onSubmit={handleNewPassword}>
            <p className="form-title">Set new password</p>
            <div className="form-group">
              <input
                className="input"
                type="password"
                placeholder="New password"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                required
              />
            </div>
            <div className="btn-row">
              <button className="btn btn-primary" type="submit">
                Update &amp; sign in
              </button>
            </div>
          </form>
        )}

        {/* Notes dashboard */}
        {view === "app" && (
          <div>
            <p className="form-title">New note</p>
            <div className="form-group">
              <input
                className="input"
                type="text"
                placeholder="Type your note..."
                value={note}
                onChange={(e) => setNote(e.target.value)}
              />
            </div>
            <div className="btn-row">
              <button className="btn btn-primary" onClick={handleSaveNote}>
                Save to DynamoDB
              </button>
              <button className="btn btn-ghost" onClick={handleSignOut}>
                Sign out
              </button>
            </div>
          </div>
        )}

        {/* Status message */}
        {status && (
          <p className={`status${isError ? " error" : ""}`}>{status}</p>
        )}
      </div>
    </div>
  );
}

export default App;
```

## File: serverless-frontend/src/main.jsx
```javascript
import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App.jsx";
import "./index.css";

// 1. Import Amplify
import { Amplify } from "aws-amplify";

// 2. Configure it with your Terraform Backend
Amplify.configure({
  Auth: {
    Cognito: {
      userPoolId: import.meta.env.VITE_USER_POOL_ID,
      userPoolClientId: import.meta.env.VITE_USER_POOL_CLIENT_ID,
      // We don't have an Identity Pool yet, so we leave it out
    },
  },
  API: {
    REST: {
      NotesAPI: {
        endpoint: import.meta.env.VITE_API_ENDPOINT,
        region: import.meta.env.VITE_AWS_REGION,
      },
    },
  },
});

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
```

## File: serverless-frontend/.gitignore
```
# Logs
logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*
pnpm-debug.log*
lerna-debug.log*

node_modules
dist
dist-ssr
*.local

# Environment variables (secrets)
.env
.env.local
.env.*.local

# Editor directories and files
.vscode/*
!.vscode/extensions.json
.idea
.DS_Store
*.suo
*.ntvs*
*.njsproj
*.sln
*.sw?
```

## File: serverless-frontend/.repomixignore
```
# Repomix Output
repomix-output.txt
repomix-output.json
repomix-output.xml
repomix-output.md

# Vite Build Output
dist/
build/

# Lockfiles (Save thousands of tokens)
package-lock.json
yarn.lock
pnpm-lock.yaml
bun.lockb

# Static Assets & Public Folder (Images, SVGs, Fonts)
public/
src/assets/
**/*.svg
**/*.png
**/*.jpg
**/*.jpeg
**/*.gif
**/*.ico
**/*.css

# Testing (Ignore unless prompts specifically require testing context)
coverage/
**/*.test.{js,jsx,ts,tsx}
**/*.spec.{js,jsx,ts,tsx}
**/__tests__/

# Continuous Integration & IDEs
.github/
.vscode/
.idea/

# Environment Local Secrets (Repomix blocks these naturally, but good to ensure)
.env*.local
```

## File: serverless-frontend/eslint.config.js
```javascript
import js from '@eslint/js'
import globals from 'globals'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import { defineConfig, globalIgnores } from 'eslint/config'

export default defineConfig([
  globalIgnores(['dist']),
  {
    files: ['**/*.{js,jsx}'],
    extends: [
      js.configs.recommended,
      reactHooks.configs.flat.recommended,
      reactRefresh.configs.vite,
    ],
    languageOptions: {
      globals: globals.browser,
      parserOptions: { ecmaFeatures: { jsx: true } },
    },
  },
])
```

## File: serverless-frontend/index.html
```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>serverless-frontend</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
```

## File: serverless-frontend/package.json
```json
{
  "name": "serverless-frontend",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "lint": "eslint .",
    "preview": "vite preview"
  },
  "dependencies": {
    "aws-amplify": "^6.20.0",
    "react": "^19.2.8",
    "react-dom": "^19.2.8"
  },
  "devDependencies": {
    "@eslint/js": "^10.0.1",
    "@types/react": "^19.2.17",
    "@types/react-dom": "^19.2.3",
    "@vitejs/plugin-react": "^6.0.4",
    "eslint": "^10.8.0",
    "eslint-plugin-react-hooks": "^7.1.1",
    "eslint-plugin-react-refresh": "^0.5.3",
    "globals": "^17.7.0",
    "vite": "^8.2.0"
  }
}
```

## File: serverless-frontend/README.md
```markdown
# React + Vite

This template provides a minimal setup to get React working in Vite with HMR and some ESLint rules.

Currently, two official plugins are available:

- [@vitejs/plugin-react](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react) uses [Oxc](https://oxc.rs)
- [@vitejs/plugin-react-swc](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react-swc) uses [SWC](https://swc.rs/)

## React Compiler

The React Compiler is not enabled on this template because of its impact on dev & build performances. To add it, see [this documentation](https://react.dev/learn/react-compiler/installation).

## Expanding the ESLint configuration

If you are developing a production application, we recommend using TypeScript with type-aware lint rules enabled. Check out the [TS template](https://github.com/vitejs/vite/tree/main/packages/create-vite/template-react-ts) for information on how to integrate TypeScript and [`typescript-eslint`](https://typescript-eslint.io) in your project.
```

## File: serverless-frontend/vite.config.js
```javascript
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
})
```

## File: .gitignore
```
# Local .terraform directories
**/.terraform/*

# .tfstate files
*.tfstate
*.tfstate.*

# Crash log files
crash.log
crash.*.log

# Exclude all .tfvars files, which contain sensitive data (passwords, AWS keys, etc.)
*.tfvars
*.tfvars.json

# Ignore override files used for local testing
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# Ignore CLI configuration files
.terraformrc
terraform.rc

# Ignore Mac/Windows system files (optional but recommended)
.DS_Store
Thumbs.db
```

## File: .repomixignore
```
# Repomix Output
repomix-output.*

# Local Terraform directories (Contains heavy provider binaries)
.terraform/

# Terraform State Files (CRITICAL: Contains secrets & plain-text passwords)
*.tfstate
*.tfstate.*
crash.log
*.crash.log

# Terraform Variables (Often contains real secrets/keys)
*.tfvars
*.tfvars.json

# Override files
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# CLI Configuration & Plan files
.terraformrc
terraform.rc
.terraform.lock.hcl
*.tfplan

# Terragrunt cache (If you use Terragrunt)
.terragrunt-cache/

# IDE and OS files
.vscode/
.idea/
.DS_Store
```

## File: index.html
```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Serverless Notes App</title>
    <style>
      body {
        font-family: Arial, sans-serif;
        padding: 50px;
        max-width: 500px;
        margin: auto;
      }
      .box {
        border: 1px solid #ccc;
        padding: 20px;
        border-radius: 8px;
        margin-bottom: 20px;
      }
      input,
      button {
        width: 100%;
        padding: 10px;
        margin: 10px 0;
        box-sizing: border-box;
      }
      button {
        background-color: #007bff;
        color: white;
        border: none;
        cursor: pointer;
      }
      button:hover {
        background-color: #0056b3;
      }
      #status {
        color: green;
        font-weight: bold;
      }
      #error {
        color: red;
        font-weight: bold;
      }
    </style>
  </head>
  <body>
    <h2>Serverless Notes App</h2>

    <div id="message-box">
      <p id="status"></p>
      <p id="error"></p>
    </div>

    <!-- Login Form -->
    <div class="box" id="login-box">
      <h3>Step 1: Log In</h3>
      <input
        type="text"
        id="email"
        placeholder="Email (e.g., test@example.com)"
      />
      <input type="password" id="password" placeholder="Password" />
      <button onclick="login()">Log In</button>
    </div>

    <!-- Note Form (Hidden until logged in) -->
    <div class="box" id="note-box" style="display: none">
      <h3>Step 2: Save a Note</h3>
      <input
        type="text"
        id="note-text"
        placeholder="Type your secret note here..."
      />
      <button onclick="saveNote()">Save Note to Database</button>
    </div>

    <script>
      // --- PUT YOUR AWS DETAILS HERE ---
      const REGION = "us-east-1";
      const CLIENT_ID = "6vcvd9i2nr5nr214gfkb9jpktb";
      const API_URL =
        "https://k52b86rnii.execute-api.us-east-1.amazonaws.com/notes";

      // This will temporarily store the JWT token in the browser's memory
      let jwtToken = "";

      // Function 1: Log in via Cognito
      async function login() {
        const email = document.getElementById("email").value;
        const password = document.getElementById("password").value;

        document.getElementById("error").innerText = "";
        document.getElementById("status").innerText = "Logging in...";

        try {
          // We make a direct API call to the AWS Cognito Identity Provider
          const response = await fetch(
            `https://cognito-idp.${REGION}.amazonaws.com/`,
            {
              method: "POST",
              headers: {
                "Content-Type": "application/x-amz-json-1.1",
                "X-Amz-Target":
                  "AWSCognitoIdentityProviderService.InitiateAuth",
              },
              body: JSON.stringify({
                AuthFlow: "USER_PASSWORD_AUTH",
                ClientId: CLIENT_ID,
                AuthParameters: {
                  USERNAME: email,
                  PASSWORD: password,
                },
              }),
            },
          );

          const data = await response.json();

          if (response.ok) {
            // Success! Extract the ID Token (The VIP Wristband)
            jwtToken = data.AuthenticationResult.IdToken;
            document.getElementById("status").innerText =
              "Successfully logged in!";
            document.getElementById("login-box").style.display = "none";
            document.getElementById("note-box").style.display = "block";
          } else {
            document.getElementById("status").innerText = "";
            document.getElementById("error").innerText =
              data.message || "Login failed.";
          }
        } catch (err) {
          document.getElementById("status").innerText = "";
          document.getElementById("error").innerText =
            "Network error occurred.";
        }
      }

      // Function 2: Save Note via API Gateway
      async function saveNote() {
        const noteText = document.getElementById("note-text").value;

        document.getElementById("error").innerText = "";
        document.getElementById("status").innerText = "Saving note...";

        try {
          const response = await fetch(API_URL, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              // CRITICAL: We attach the Cognito token here!
              Authorization: jwtToken,
            },
            body: JSON.stringify({
              Note: noteText,
            }),
          });

          if (response.ok) {
            document.getElementById("status").innerText =
              "Note successfully saved to DynamoDB!";
            document.getElementById("note-text").value = ""; // clear the box
          } else {
            document.getElementById("status").innerText = "";
            document.getElementById("error").innerText =
              "Failed to save. Unauthorized or server error.";
          }
        } catch (err) {
          document.getElementById("status").innerText = "";
          document.getElementById("error").innerText =
            "Network error connecting to API.";
        }
      }
    </script>
  </body>
</html>
```

## File: lambda_function.py
```python
import json
import boto3
import uuid
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TABLE_NAME = os.environ.get('TABLE_NAME', 'NotesTable')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    try:
        authorizer = event.get('requestContext', {}).get('authorizer', {})
        
        jwt_claims = authorizer.get('jwt', {}).get('claims')
        
        if not jwt_claims:
            jwt_claims = authorizer.get('claims', {})
            
        user_id = jwt_claims.get('sub')
        
        if not user_id:
            logger.error(f"Unauthorized attempt. Payload received: {json.dumps(event)}")
            return {"statusCode": 401, "body": json.dumps("Unauthorized - Missing Sub Claim")}

        body = json.loads(event.get('body', '{}'))
        note_content = body.get('Note')
        
        if not note_content:
            return {"statusCode": 400, "body": json.dumps("Note content is required.")}
            
        note_id = str(uuid.uuid4())
        
        table.put_item(
            Item={
                'UserId': user_id,
                'NoteId': note_id,
                'Note': note_content
            }
        )
        
        logger.info(json.dumps({"message": "Note created successfully", "user_id": user_id, "note_id": note_id}))
        
        return {
            'statusCode': 201,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'NoteId': note_id, 'Message': 'Successfully saved note'})
        }
        
    except json.JSONDecodeError:
        logger.error("Invalid JSON payload provided.")
        return {"statusCode": 400, "body": json.dumps("Invalid JSON payload")}
    except Exception as e:
        logger.exception("Internal Server Error occurred.")
        return {"statusCode": 500, "body": json.dumps("Internal Server Error")}
```

## File: main.tf
```hcl
# 2. Create the DynamoDB Table
resource "aws_dynamodb_table" "notes_table" {
  name         = "NotesTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "UserId"
  range_key    = "NoteId"

  attribute {
    name = "UserId"
    type = "S"
  }

  attribute {
    name = "NoteId"
    type = "S"
  }
}

# 3. Create the IAM Role for Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "create_note_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# 4. Attach DynamoDB Access to the Lambda Role
resource "aws_iam_role_policy_attachment" "lambda_dynamodb_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

# Attach Basic Execution Role (Allows Lambda to write logs to CloudWatch)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 5. Zip the Python Code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

# 6. Create the Lambda Function
resource "aws_lambda_function" "create_note_function" {
  filename      = "lambda_function.zip"
  function_name = "CreateNoteFunction"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.notes_table.name
    }
  }
}

# 7. Create the HTTP API Gateway
resource "aws_apigatewayv2_api" "http_api" {
  name          = "NotesAPI"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "GET", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }
}

# 8. Connect API Gateway to Lambda (Integration)
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.create_note_function.invoke_arn
}

# 9. Create the Route (POST /notes)
resource "aws_apigatewayv2_route" "post_route" {
  api_id             = aws_apigatewayv2_api.http_api.id
  route_key          = "POST /notes"
  target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_authorizer.id
}

# 10. Deploy the API Gateway Stage
resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

# 11. Give API Gateway permission to trigger the Lambda function
resource "aws_lambda_permission" "api_gw_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_note_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# Output the Live API URL so you can test it immediately
output "api_endpoint" {
  value = aws_apigatewayv2_api.http_api.api_endpoint
}

# 12. Create the Cognito User Pool (The User Directory)
resource "aws_cognito_user_pool" "user_pool" {
  name = "NotesAppUsers"

  # Email IS the username — prevents duplicate accounts at sign-up time
  # (alias_attributes allows duplicates until confirmation; username_attributes does not)
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }
}

# 13. Create the Cognito App Client (For the Frontend to talk to)
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "NotesAppFrontendClient"
  user_pool_id = aws_cognito_user_pool.user_pool.id

  # We set this to false because web browsers (JavaScript) cannot securely hide secrets
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}

# 14. Create the API Gateway Authorizer (The Bouncer)
resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id           = aws_apigatewayv2_api.http_api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "CognitoJWTAuthorizer"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.user_pool_client.id]
    issuer   = "https://${aws_cognito_user_pool.user_pool.endpoint}"
  }
}
```

## File: outputs.tf
```hcl
output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool (For Amplify userPoolId)"
  value       = aws_cognito_user_pool.user_pool.id
}

output "cognito_client_id" {
  description = "The ID of the Cognito App Client (For Amplify userPoolClientId)"
  value       = aws_cognito_user_pool_client.user_pool_client.id
}

output "api_gateway_url" {
  description = "The base URL of the API Gateway (For Amplify endpoint)"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}
```

## File: provider.tf
```hcl
provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    bucket = "my-tf-state-bucket-myint"
    key    = "serverless-webapp-project/terraform.tfstate"
    region = "us-east-1"
  }

  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
```
