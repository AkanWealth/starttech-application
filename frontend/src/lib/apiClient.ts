import axios from 'axios';

// The frontend and the API share one CloudFront domain: CloudFront sends
// /api/* to the backend load balancer, so a relative base URL avoids both
// mixed-content blocking and CORS. In local development, Vite proxies /api
// to the backend (see vite.config.ts).
const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || '/api/v1';

export const apiClient = axios.create({
    baseURL: API_BASE_URL,
    withCredentials: true, // Crucial for httpOnly cookies
});
