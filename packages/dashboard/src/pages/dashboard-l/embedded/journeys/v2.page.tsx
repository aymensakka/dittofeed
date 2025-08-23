import React from "react";
import { GetServerSideProps } from "next";
import { useRouter } from "next/router";
import EmbeddedLayout from "../../../../components/embeddedLayout";
import JourneyEditor from "../../../../components/journeys/v2/editor";
import { Box } from "@mui/material";

export const getServerSideProps: GetServerSideProps = async (context) => {
  const { token, workspaceId, id } = context.query;

  // Basic validation on server side
  if (!token || !workspaceId) {
    return {
      notFound: true,
    };
  }

  return {
    props: {
      token,
      workspaceId,
      journeyId: id || null,
    },
  };
};

interface EmbeddedJourneyEditorProps {
  token: string;
  workspaceId: string;
  journeyId: string | null;
}

export default function EmbeddedJourneyEditor({ 
  token, 
  workspaceId, 
  journeyId 
}: EmbeddedJourneyEditorProps) {
  return (
    <EmbeddedLayout>
      <Box sx={{ height: '100vh', display: 'flex', flexDirection: 'column' }}>
        <JourneyEditor />
      </Box>
    </EmbeddedLayout>
  );
}