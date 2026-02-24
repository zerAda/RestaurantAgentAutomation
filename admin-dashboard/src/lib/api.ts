import axios from "axios";

export const api = axios.create({
    baseURL: import.meta.env.VITE_API_URL || "http://localhost:5678/webhook",
    headers: {
        "Content-Type": "application/json",
    },
});
