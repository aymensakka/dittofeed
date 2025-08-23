import axios, { AxiosInstance } from "axios";

// Helper function to get JWT from cookies or embedded session
function getJwtFromCookies(): string | null {
  if (typeof document === 'undefined') return null;
  
  // Check for embedded session token first
  if (typeof sessionStorage !== 'undefined') {
    const embeddedToken = sessionStorage.getItem('embeddedToken');
    if (embeddedToken) {
      return embeddedToken;
    }
  }
  
  const cookies = document.cookie.split('; ');
  
  // First check for transfer cookie (temporary)
  const transferCookie = cookies.find(c => c.startsWith('df-jwt-transfer='));
  if (transferCookie) {
    const jwt = transferCookie.split('=')[1];
    // Store in localStorage and remove transfer cookie
    if (jwt && jwt !== 'undefined') {
      localStorage.setItem('df-jwt', jwt);
      // Remove the transfer cookie
      document.cookie = 'df-jwt-transfer=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT';
      return jwt;
    }
  }
  
  // Check localStorage
  const storedJwt = localStorage.getItem('df-jwt');
  if (storedJwt && storedJwt !== 'undefined') {
    return storedJwt;
  }
  
  // Note: df-jwt cookie is httpOnly and cannot be read by JavaScript
  // That's why we use localStorage after transferring from df-jwt-transfer
  
  return null;
}

// Create a pre-configured axios instance for multi-tenant mode
const axiosInstance: AxiosInstance = axios.create({
  // Include cookies in all requests for multi-tenant authentication
  withCredentials: true,
});

// Add request interceptor to include JWT token and log requests
axiosInstance.interceptors.request.use(
  (config) => {
    // Add JWT token to Authorization header if available
    const jwt = getJwtFromCookies();
    if (jwt) {
      config.headers.Authorization = `Bearer ${jwt}`;
    }
    
    // Add workspace ID header for embedded sessions
    if (typeof sessionStorage !== 'undefined') {
      const embeddedWorkspaceId = sessionStorage.getItem('embeddedWorkspaceId');
      if (embeddedWorkspaceId) {
        config.headers['X-Workspace-Id'] = embeddedWorkspaceId;
      }
    }
    
    if (process.env.NODE_ENV === "development") {
      console.log("API Request:", config.method?.toUpperCase(), config.url, "JWT:", !!jwt);
    }
    return config;
  },
  (error) => {
    console.error("Request error:", error);
    return Promise.reject(error);
  }
);

if (process.env.NODE_ENV === "development") {
  axiosInstance.interceptors.response.use(
    (response) => {
      return response;
    },
    (error) => {
      console.error("API Error:", error.response?.status, error.response?.data);
      return Promise.reject(error);
    }
  );
}

export default axiosInstance;
