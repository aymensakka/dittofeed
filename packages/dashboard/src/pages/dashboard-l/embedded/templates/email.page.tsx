import React from "react";
import { GetServerSideProps } from "next";
import EmbeddedLayout from "../../../../components/embeddedLayout";
import EmailEditor from "../../../../components/messages/emailEditor";

export const getServerSideProps: GetServerSideProps = async (context) => {
  const { token, workspaceId, id } = context.query;

  if (!token || !workspaceId || !id) {
    return {
      notFound: true,
    };
  }

  return {
    props: {
      token,
      workspaceId,
      templateId: id,
    },
  };
};

interface EmbeddedEmailEditorProps {
  token: string;
  workspaceId: string;
  templateId: string;
}

export default function EmbeddedEmailEditor({ 
  token, 
  workspaceId, 
  templateId 
}: EmbeddedEmailEditorProps) {
  return (
    <EmbeddedLayout>
      <EmailEditor templateId={templateId} />
    </EmbeddedLayout>
  );
}