import { useState, useEffect } from "react";
import {
  signIn,
  confirmSignIn,
  signOut,
  getCurrentUser,
  fetchAuthSession,
} from "aws-amplify/auth";
import { post } from "aws-amplify/api";
import "./App.css";

function App() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [note, setNote] = useState("");

  // State Machine Flags
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [requiresNewPassword, setRequiresNewPassword] = useState(false);
  const [status, setStatus] = useState("");

  // Restore session on page load so login form doesn't show when
  // Amplify already has a valid Cognito session in localStorage.
  useEffect(() => {
    getCurrentUser()
      .then(() => setIsLoggedIn(true))
      .catch(() => {}); // no session — stay on login screen
  }, []);

  const isError =
    status.toLowerCase().startsWith("error") ||
    status.toLowerCase().startsWith("failed");

  // --- 1. HANDLE LOGIN & CHALLENGES ---
  const handleLogin = async (e) => {
    e.preventDefault();
    setStatus("Logging in...");
    try {
      const { nextStep } = await signIn({ username: email, password });

      if (
        nextStep.signInStep === "CONFIRM_SIGN_IN_WITH_NEW_PASSWORD_REQUIRED"
      ) {
        setRequiresNewPassword(true);
        setStatus(
          "Admin password detected. Please set a new permanent password.",
        );
      } else if (nextStep.signInStep === "DONE") {
        setIsLoggedIn(true);
        setStatus("Successfully logged in!");
      }
    } catch (err) {
      // If a stale session is lingering, sign it out and retry once.
      if (err.name === "UserAlreadyAuthenticatedException") {
        try {
          await signOut();
          const { nextStep } = await signIn({ username: email, password });
          if (
            nextStep.signInStep === "CONFIRM_SIGN_IN_WITH_NEW_PASSWORD_REQUIRED"
          ) {
            setRequiresNewPassword(true);
            setStatus(
              "Admin password detected. Please set a new permanent password.",
            );
          } else if (nextStep.signInStep === "DONE") {
            setIsLoggedIn(true);
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

  // --- 2. COMPLETE THE PASSWORD CHALLENGE ---
  const handleNewPassword = async (e) => {
    e.preventDefault();
    try {
      const { nextStep } = await confirmSignIn({
        challengeResponse: newPassword,
      });
      if (nextStep.signInStep === "DONE") {
        setRequiresNewPassword(false);
        setIsLoggedIn(true);
        setNewPassword("");
        setStatus("Password updated and successfully logged in!");
      }
    } catch (err) {
      setNewPassword("");
      setStatus(`Error: ${err.message}`);
    }
  };

  // --- 3. SECURE API CALL ---
  const handleSaveNote = async () => {
    if (!note.trim()) {
      setStatus("Error: Note cannot be empty.");
      return;
    }
    setStatus("Saving note...");
    try {
      // Get the current secure session (Amplify manages the JWT for us)
      const session = await fetchAuthSession();
      if (!session.tokens?.idToken) {
        setStatus("Error: Session expired. Please sign in again.");
        setIsLoggedIn(false);
        return;
      }
      const token = session.tokens.idToken.toString();

      // Make the API Call; Amplify routes it to the endpoint configured in main.jsx
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

  const handleSignOut = async () => {
    await signOut();
    setIsLoggedIn(false);
    setEmail("");
    setPassword("");
    setNote("");
    setStatus("");
  };

  return (
    <div className="app-shell">
      <div className="card">
        {/* Header */}
        <div className="card-header">
          <h1>Serverless Notes</h1>
          <p>Secured with AWS Cognito + API Gateway</p>
        </div>

        {/* Login form */}
        {!isLoggedIn && !requiresNewPassword && (
          <form onSubmit={handleLogin}>
            <p className="form-title">Sign in</p>
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

        {/* New password challenge */}
        {requiresNewPassword && (
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
                Update & sign in
              </button>
            </div>
          </form>
        )}

        {/* Notes dashboard */}
        {isLoggedIn && (
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
