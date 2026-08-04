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
