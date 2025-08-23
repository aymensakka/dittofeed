import { Box, CssBaseline, ThemeProvider } from "@mui/material";
import React, { PropsWithChildren, useEffect, useState } from "react";
import { useRouter } from "next/router";
import theme from "../themeCustomization";
import createEmotionCache from "../lib/createEmotionCache";
import { CacheProvider } from "@emotion/react";

const clientSideEmotionCache = createEmotionCache();

interface EmbeddedLayoutProps extends PropsWithChildren {
  allowedOrigins?: string[];
}

export default function EmbeddedLayout({ 
  children,
  allowedOrigins = ["*"]
}: EmbeddedLayoutProps) {
  const router = useRouter();
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [isLoading, setIsLoading] = useState(true);
  
  useEffect(() => {
    // Verify session token from query parameters
    const { token, workspaceId } = router.query;
    
    if (!token || !workspaceId) {
      setIsLoading(false);
      return;
    }

    // Verify the session token
    fetch('/api-l/sessions/verify', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ token }),
    })
      .then(res => res.json())
      .then(data => {
        if (data.valid && data.workspaceId === workspaceId) {
          setIsAuthenticated(true);
          
          // Store token and workspace in session storage for subsequent requests
          sessionStorage.setItem('embeddedToken', token as string);
          sessionStorage.setItem('embeddedWorkspaceId', workspaceId as string);
        }
        setIsLoading(false);
      })
      .catch(() => {
        setIsLoading(false);
      });

    // Set up postMessage communication with parent window
    if (window.parent !== window) {
      const handleMessage = (event: MessageEvent) => {
        // Verify origin if specified
        if (allowedOrigins[0] !== "*" && !allowedOrigins.includes(event.origin)) {
          return;
        }

        // Handle different message types
        if (event.data.type === 'resize') {
          // Parent can request iframe to report its size
          const height = document.body.scrollHeight;
          window.parent.postMessage({
            type: 'height',
            height,
          }, event.origin);
        }
      };

      window.addEventListener('message', handleMessage);
      
      // Notify parent that iframe is ready
      window.parent.postMessage({
        type: 'ready',
        workspaceId,
      }, '*');

      return () => {
        window.removeEventListener('message', handleMessage);
      };
    }
  }, [router.query, allowedOrigins]);

  if (isLoading) {
    return (
      <CacheProvider value={clientSideEmotionCache}>
        <ThemeProvider theme={theme()}>
          <CssBaseline />
          <Box
            sx={{
              display: 'flex',
              justifyContent: 'center',
              alignItems: 'center',
              height: '100vh',
              backgroundColor: 'background.default',
            }}
          >
            Loading...
          </Box>
        </ThemeProvider>
      </CacheProvider>
    );
  }

  if (!isAuthenticated) {
    return (
      <CacheProvider value={clientSideEmotionCache}>
        <ThemeProvider theme={theme()}>
          <CssBaseline />
          <Box
            sx={{
              display: 'flex',
              justifyContent: 'center',
              alignItems: 'center',
              height: '100vh',
              backgroundColor: 'background.default',
              color: 'error.main',
            }}
          >
            Invalid or expired session token
          </Box>
        </ThemeProvider>
      </CacheProvider>
    );
  }

  return (
    <CacheProvider value={clientSideEmotionCache}>
      <ThemeProvider theme={theme()}>
        <CssBaseline />
        <Box
          sx={{
            width: '100%',
            minHeight: '100vh',
            backgroundColor: 'background.default',
            p: 2,
          }}
        >
          {children}
        </Box>
      </ThemeProvider>
    </CacheProvider>
  );
}