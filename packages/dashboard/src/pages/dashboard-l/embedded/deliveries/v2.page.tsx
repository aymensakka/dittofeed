import React from "react";
import { GetServerSideProps } from "next";
import EmbeddedLayout from "../../../../components/embeddedLayout";
import { DeliveriesTableV2 } from "../../../../components/deliveriesTableV2";
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

interface EmbeddedDeliveriesProps {
  token: string;
  workspaceId: string;
}

export default function EmbeddedDeliveries({ token, workspaceId }: EmbeddedDeliveriesProps) {
  return (
    <EmbeddedLayout>
      <Box>
        <Typography variant="h4" sx={{ mb: 3 }}>
          Deliveries
        </Typography>
        <DeliveriesTableV2 />
      </Box>
    </EmbeddedLayout>
  );
}