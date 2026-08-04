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
