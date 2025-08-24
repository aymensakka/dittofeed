import React from "react";
import { GetServerSideProps } from "next";
import EmbeddedLayout from "../../../components/embeddedLayout";
import BroadcastsTable from "../../../components/broadcastsTable";
import { Box, Typography } from "@mui/material";

export const getServerSideProps: GetServerSideProps = async (context) => {
  const { token, workspaceId } = context.query;

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

interface EmbeddedBroadcastsProps {
  token: string;
  workspaceId: string;
}

export default function EmbeddedBroadcasts({ token, workspaceId }: EmbeddedBroadcastsProps) {
  return (
    <EmbeddedLayout>
      <Box>
        <Typography variant="h4" sx={{ mb: 3 }}>
          Broadcasts
        </Typography>
        <BroadcastsTable />
      </Box>
    </EmbeddedLayout>
  );
}