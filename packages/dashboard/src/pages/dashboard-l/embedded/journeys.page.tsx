import React from "react";
import { GetServerSideProps } from "next";
import { useRouter } from "next/router";
import EmbeddedLayout from "../../../components/embeddedLayout";
import JourneysTable from "../../../components/journeys/v2/journeysTable";
import { Box, Typography } from "@mui/material";

export const getServerSideProps: GetServerSideProps = async (context) => {
  const { token, workspaceId } = context.query;

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
    },
  };
};

interface EmbeddedJourneysProps {
  token: string;
  workspaceId: string;
}

export default function EmbeddedJourneys({ token, workspaceId }: EmbeddedJourneysProps) {
  const router = useRouter();

  return (
    <EmbeddedLayout>
      <Box>
        <Typography variant="h4" sx={{ mb: 3 }}>
          Journeys
        </Typography>
        <JourneysTable />
      </Box>
    </EmbeddedLayout>
  );
}