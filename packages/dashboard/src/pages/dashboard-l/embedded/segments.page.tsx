import React from "react";
import { GetServerSideProps } from "next";
import EmbeddedLayout from "../../../components/embeddedLayout";
import { SegmentsTable } from "../../../components/segments/segmentsTable";
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

interface EmbeddedSegmentsProps {
  token: string;
  workspaceId: string;
}

export default function EmbeddedSegments({ token, workspaceId }: EmbeddedSegmentsProps) {
  return (
    <EmbeddedLayout>
      <Box>
        <Typography variant="h4" sx={{ mb: 3 }}>
          Segments
        </Typography>
        <SegmentsTable />
      </Box>
    </EmbeddedLayout>
  );
}