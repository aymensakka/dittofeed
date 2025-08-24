import React from "react";
import { GetServerSideProps } from "next";
import EmbeddedLayout from "../../../components/embeddedLayout";
import TemplatesTable from "../../../components/messages/templatesTable";
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

interface EmbeddedTemplatesProps {
  token: string;
  workspaceId: string;
}

export default function EmbeddedTemplates({ token, workspaceId }: EmbeddedTemplatesProps) {
  return (
    <EmbeddedLayout>
      <Box>
        <Typography variant="h4" sx={{ mb: 3 }}>
          Templates
        </Typography>
        <TemplatesTable />
      </Box>
    </EmbeddedLayout>
  );
}