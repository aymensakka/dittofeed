import { GetServerSideProps } from "next";
import Head from "next/head";
import { useRouter } from "next/router";
import { useState } from "react";

interface NoOrganizationPageProps {
  email?: string;
  message?: string;
}

export default function NoOrganizationPage({ 
  email, 
  message 
}: NoOrganizationPageProps) {
  const router = useRouter();
  const [isRetrying, setIsRetrying] = useState(false);

  const handleRetry = async () => {
    setIsRetrying(true);
    // Redirect back to the OAuth flow
    window.location.href = '/api/public/auth/oauth2/initiate/google';
  };

  const handleContactSupport = () => {
    // You can customize this to your support contact method
    window.location.href = 'mailto:support@dittofeed.com?subject=Access Request&body=' + 
      encodeURIComponent(`I need access to the Dittofeed platform. My email is: ${email || 'N/A'}`);
  };

  return (
    <>
      <Head>
        <title>No Organization Access - Dittofeed</title>
      </Head>
      <div className="min-h-screen flex items-center justify-center bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
        <div className="max-w-md w-full space-y-8">
          <div>
            <div className="mx-auto h-12 w-12 text-red-500">
              <svg
                className="h-full w-full"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
                xmlns="http://www.w3.org/2000/svg"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.082 16.5c-.77.833.192 2.5 1.732 2.5z"
                />
              </svg>
            </div>
            <h2 className="mt-6 text-center text-3xl font-extrabold text-gray-900">
              Access Denied
            </h2>
            <p className="mt-2 text-center text-sm text-gray-600">
              Your account does not have access to any organization
            </p>
          </div>
          
          <div className="bg-white shadow-sm rounded-lg p-6">
            <div className="space-y-4">
              {email && (
                <div>
                  <p className="text-sm text-gray-600">
                    <strong>Email:</strong> {email}
                  </p>
                </div>
              )}
              
              <div>
                <p className="text-sm text-gray-700">
                  {message || 
                    "Your email address is not associated with any registered organization. Please contact your administrator to get access to a workspace."
                  }
                </p>
              </div>
              
              <div className="space-y-3 pt-4">
                <button
                  onClick={handleContactSupport}
                  className="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                >
                  Contact Support
                </button>
                
                <button
                  onClick={handleRetry}
                  disabled={isRetrying}
                  className="w-full flex justify-center py-2 px-4 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50"
                >
                  {isRetrying ? "Retrying..." : "Try Again"}
                </button>
                
                <button
                  onClick={() => router.push('/dashboard')}
                  className="w-full flex justify-center py-2 px-4 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                >
                  Back to Home
                </button>
              </div>
            </div>
          </div>
          
          <div className="text-center">
            <p className="text-xs text-gray-500">
              If you believe this is an error, please contact your system administrator.
            </p>
          </div>
        </div>
      </div>
    </>
  );
}

export const getServerSideProps: GetServerSideProps = async (context) => {
  const { email, message } = context.query;
  
  return {
    props: {
      email: email ? String(email) : null,
      message: message ? String(message) : null,
    },
  };
};