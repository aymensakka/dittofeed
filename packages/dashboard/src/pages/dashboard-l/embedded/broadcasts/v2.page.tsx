import React from "react";
import { GetServerSideProps } from "next";
import { useRouter } from "next/router";
import EmbeddedLayout from "../../../../components/embeddedLayout";
import Broadcast from "../../../../components/broadcast";

export const getServerSideProps: GetServerSideProps = async (context) => {
  const { token, workspaceId, id } = context.query;

  if (!token || !workspaceId) {
    return {
      notFound: true,
    };
  }

  return {
    props: {
      token,
      workspaceId,
      broadcastId: id || null,
    },
  };
};

interface EmbeddedBroadcastEditorProps {
  token: string;
  workspaceId: string;
  broadcastId: string | null;
}

export default function EmbeddedBroadcastEditor({ 
  token, 
  workspaceId, 
  broadcastId 
}: EmbeddedBroadcastEditorProps) {
  const router = useRouter();
  const queryParams = router.query;
  
  return (
    <EmbeddedLayout>
      <Broadcast
        queryParams={queryParams}
        sx={{
          pt: 2,
          px: 1,
          pb: 1,
          width: "100%",
          height: "100%",
        }}
      />
    </EmbeddedLayout>
  );
}