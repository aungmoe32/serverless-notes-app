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
import { post, get, del, put } from "aws-amplify/api";
import { uploadData, getUrl } from "aws-amplify/storage";
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
  const [file, setFile] = useState(null);
  const [notesList, setNotesList] = useState([]);
  const [editingNoteId, setEditingNoteId] = useState(null);
  const [editNoteText, setEditNoteText] = useState("");
  const [status, setStatus] = useState("");

  const isError =
    status.toLowerCase().startsWith("error") ||
    status.toLowerCase().startsWith("failed");

  // --- FETCH ALL NOTES (WITH S3 PRE-SIGNED URLS) ---
  const fetchNotes = async () => {
    try {
      const session = await fetchAuthSession();
      if (!session.tokens?.idToken) return;
      const token = session.tokens.idToken.toString();
      const identityId = session.identityId;

      // 1. Fetch notes from API Gateway / DynamoDB
      const restOperation = get({
        apiName: "NotesAPI",
        path: "/notes",
        options: { headers: { Authorization: token } },
      });

      const response = await restOperation.response;
      const data = await response.body.json();

      // 2. Generate secure pre-signed URLs for attachments
      const notesWithUrls = await Promise.all(
        (Array.isArray(data) ? data : []).map(async (noteItem) => {
          if (noteItem.Attachment && identityId) {
            try {
              const s3Path = `private/${identityId}/${noteItem.Attachment}`;
              const linkToStorageFile = await getUrl({ path: s3Path });
              return {
                ...noteItem,
                AttachmentUrl: linkToStorageFile.url.toString(),
              };
            } catch (err) {
              console.error(
                `Failed to get URL for ${noteItem.Attachment}`,
                err,
              );
            }
          }
          return noteItem;
        }),
      );

      // 3. Update the UI state
      setNotesList(notesWithUrls);
    } catch (err) {
      console.error(err);
      setStatus(`Failed to fetch notes: ${err.message}`);
    }
  };

  // Restore session on page load
  useEffect(() => {
    getCurrentUser()
      .then(() => {
        setView("app");
        fetchNotes();
      })
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
        username: email,
        password,
        options: { userAttributes: { email } },
      });
      if (nextStep.signUpStep === "CONFIRM_SIGN_UP") {
        setStatus("Check your email for a verification code.");
        setView("verify");
      } else if (nextStep.signUpStep === "DONE") {
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
        fetchNotes();
      }
    } catch (err) {
      if (err.name === "UserAlreadyAuthenticatedException") {
        try {
          await signOut();
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
            fetchNotes();
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
        fetchNotes();
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
    setStatus("Saving...");
    try {
      const session = await fetchAuthSession();
      if (!session.tokens?.idToken) {
        setStatus("Error: Session expired. Please sign in again.");
        setView("login");
        return;
      }

      let attachmentKey = null;
      let attachmentUrl = null;

      // --- DIRECT S3 UPLOAD ---
      if (file) {
        setStatus("Uploading file directly to S3...");
        const s3Path = `private/${session.identityId}/${file.name}`;

        const uploadTask = uploadData({
          path: s3Path,
          data: file,
        });

        await uploadTask.result;
        attachmentKey = file.name;

        try {
          const linkToStorageFile = await getUrl({ path: s3Path });
          attachmentUrl = linkToStorageFile.url.toString();
        } catch (urlErr) {
          console.error("Failed to generate pre-signed URL:", urlErr);
        }
      }

      // --- SAVE NOTE TO DYNAMODB ---
      setStatus("Saving note to database...");
      const token = session.tokens.idToken.toString();

      const restOperation = post({
        apiName: "NotesAPI",
        path: "/notes",
        options: {
          headers: { Authorization: token },
          body: {
            Note: note,
            Attachment: attachmentKey,
          },
        },
      });

      const response = await restOperation.response;
      const data = await response.body.json();

      setStatus("Note saved!");
      setNote("");
      setFile(null);
      const fileInput = document.getElementById("file-input");
      if (fileInput) fileInput.value = "";

      setNotesList((prev) => [
        ...prev,
        {
          NoteId: data.NoteId,
          Note: note,
          Attachment: attachmentKey,
          AttachmentUrl: attachmentUrl,
        },
      ]);
    } catch (err) {
      console.error(err);
      setStatus(`Failed: ${err.message}`);
    }
  };

  // ── 6. UPDATE NOTE ───────────────────────────────────────────
  const handleUpdateNote = async (noteId) => {
    if (!editNoteText.trim()) return;

    setNotesList((prevNotes) =>
      prevNotes.map((n) =>
        n.NoteId === noteId ? { ...n, Note: editNoteText } : n,
      ),
    );

    setEditingNoteId(null);
    setEditNoteText("");
    setStatus("Updating note...");

    try {
      const session = await fetchAuthSession();
      if (!session.tokens?.idToken) {
        setStatus("Error: Session expired. Please sign in again.");
        setView("login");
        return;
      }
      const token = session.tokens.idToken.toString();

      const restOperation = put({
        apiName: "NotesAPI",
        path: `/notes/${noteId}`,
        options: {
          headers: { Authorization: token },
          body: { Note: editNoteText },
        },
      });

      await restOperation.response;
      setStatus("Note successfully updated!");
    } catch (err) {
      console.error(err);
      setStatus(`Failed to update note: ${err.message}`);
      fetchNotes();
    }
  };

  // ── 7. DELETE NOTE ───────────────────────────────────────────
  const handleDeleteNote = async (noteId) => {
    setNotesList((prevNotes) => prevNotes.filter((n) => n.NoteId !== noteId));

    try {
      const session = await fetchAuthSession();
      if (!session.tokens?.idToken) {
        setStatus("Error: Session expired. Please sign in again.");
        setView("login");
        return;
      }
      const token = session.tokens.idToken.toString();

      const restOperation = del({
        apiName: "NotesAPI",
        path: `/notes/${noteId}`,
        options: { headers: { Authorization: token } },
      });

      await restOperation.response;
      setStatus("Note deleted.");
    } catch (err) {
      console.error(err);
      setStatus(`Failed to delete note: ${err.message}`);
      fetchNotes();
    }
  };

  // ── 8. SIGN OUT ──────────────────────────────────────────────
  const handleSignOut = async () => {
    await signOut();
    setView("login");
    setEmail("");
    setPassword("");
    setNote("");
    setFile(null);
    const fileInput = document.getElementById("file-input");
    if (fileInput) fileInput.value = "";
    setNotesList([]);
    setEditingNoteId(null);
    setEditNoteText("");
    setStatus("");
  };

  // ── RENDER ───────────────────────────────────────────────────
  return (
    <div className="app-shell">
      <div className="card">
        {/* Header */}
        <div className="card-header">
          {/* <div className="brand-badge">⚡ Cloud Native Serverless</div> */}
          <h1>Serverless Notes</h1>
          <p>Secured with AWS Cognito, API Gateway &amp; S3</p>
        </div>

        {/* Tab bar — only on login / signup views */}
        {(view === "login" || view === "signup") && (
          <div className="tab-bar">
            <button
              className={`tab${view === "login" ? " tab-active" : ""}`}
              onClick={() => {
                setView("login");
                setStatus("");
              }}
              type="button"
            >
              Sign In
            </button>
            <button
              className={`tab${view === "signup" ? " tab-active" : ""}`}
              onClick={() => {
                setView("signup");
                setStatus("");
              }}
              type="button"
            >
              Sign Up
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
                Sign In
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
                Create Account
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
                onClick={() => {
                  setView("login");
                  setStatus("");
                }}
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
                Update &amp; Sign In
              </button>
            </div>
          </form>
        )}

        {/* Notes dashboard */}
        {view === "app" && (
          <div>
            <p className="form-title">New Note</p>
            <div className="form-group">
              <input
                className="input"
                type="text"
                placeholder="Type your note..."
                value={note}
                onChange={(e) => setNote(e.target.value)}
              />
              <input
                id="file-input"
                className="input"
                type="file"
                onChange={(e) => setFile(e.target.files[0] || null)}
              />
            </div>
            <div className="btn-row">
              <button className="btn btn-primary" onClick={handleSaveNote}>
                Save to DynamoDB
              </button>
              <button className="btn btn-ghost" onClick={handleSignOut}>
                Sign Out
              </button>
            </div>

            <div className="notes-container">
              <div className="notes-header">
                <p className="form-title">Your Notes</p>
                <span
                  style={{
                    fontSize: "12px",
                    color: "var(--text-muted)",
                    fontWeight: 600,
                  }}
                >
                  {notesList.length} {notesList.length === 1 ? "item" : "items"}
                </span>
              </div>

              {notesList.length === 0 ? (
                <p
                  style={{
                    fontSize: "13px",
                    color: "var(--text-muted)",
                    marginTop: "8px",
                  }}
                >
                  No notes found. Create your first note above!
                </p>
              ) : (
                <ul
                  style={{
                    listStyleType: "none",
                    padding: 0,
                    margin: "8px 0 0 0",
                  }}
                >
                  {notesList.map((n) => (
                    <li key={n.NoteId} className="note-item">
                      {editingNoteId === n.NoteId ? (
                        <div
                          style={{
                            display: "flex",
                            width: "100%",
                            gap: "8px",
                            alignItems: "center",
                          }}
                        >
                          <input
                            className="input"
                            type="text"
                            value={editNoteText}
                            onChange={(e) => setEditNoteText(e.target.value)}
                            style={{ flexGrow: 1 }}
                          />
                          <button
                            className="btn btn-primary"
                            onClick={() => handleUpdateNote(n.NoteId)}
                            style={{ padding: "8px 14px", fontSize: "12px" }}
                          >
                            Save
                          </button>
                          <button
                            className="btn btn-ghost"
                            onClick={() => setEditingNoteId(null)}
                            style={{ padding: "8px 14px", fontSize: "12px" }}
                          >
                            Cancel
                          </button>
                        </div>
                      ) : (
                        <>
                          <div className="note-content">
                            <span className="note-text">{n.Note}</span>

                            {/* PRE-SIGNED S3 ATTACHMENT DISPLAY */}
                            {n.AttachmentUrl && (
                              <div style={{ marginTop: "4px" }}>
                                <img
                                  src={n.AttachmentUrl}
                                  alt="Attachment preview"
                                  className="attachment-preview-img"
                                  onError={(e) => {
                                    e.target.style.display = "none";
                                  }}
                                />
                                <a
                                  href={n.AttachmentUrl}
                                  target="_blank"
                                  rel="noopener noreferrer"
                                  className="attachment-link"
                                >
                                  📎 Open {n.Attachment || "Attachment"}
                                </a>
                              </div>
                            )}

                            {n.Attachment && !n.AttachmentUrl && (
                              <span className="attachment-badge">
                                📎 {n.Attachment}
                              </span>
                            )}
                          </div>

                          <div className="note-actions">
                            <button
                              className="btn btn-ghost"
                              onClick={() => {
                                setEditingNoteId(n.NoteId);
                                setEditNoteText(n.Note);
                              }}
                              style={{ padding: "5px 10px", fontSize: "12px" }}
                            >
                              Edit
                            </button>
                            <button
                              className="btn btn-danger"
                              onClick={() => handleDeleteNote(n.NoteId)}
                              style={{ padding: "5px 10px", fontSize: "12px" }}
                            >
                              Delete
                            </button>
                          </div>
                        </>
                      )}
                    </li>
                  ))}
                </ul>
              )}
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
