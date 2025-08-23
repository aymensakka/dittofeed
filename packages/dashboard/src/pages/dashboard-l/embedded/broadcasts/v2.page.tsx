import React from "react";
import { GetServerSideProps } from "next";
import EmbeddedLayout from "../../../../components/embeddedLayout";
import BroadcastLayoutV2 from "../../../../components/broadcasts/broadcastsLayoutV2";

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
  return (
    <EmbeddedLayout>
      <BroadcastLayoutV2 />
    </EmbeddedLayout>
  );
}