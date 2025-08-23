import React from "react";
import { GetServerSideProps } from "next";
import EmbeddedLayout from "../../../../components/embeddedLayout";
import SmsEditor from "../../../../components/messages/smsEditor";

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

interface EmbeddedSmsEditorProps {
  token: string;
  workspaceId: string;
  templateId: string;
}

export default function EmbeddedSmsEditor({ 
  token, 
  workspaceId, 
  templateId 
}: EmbeddedSmsEditorProps) {
  return (
    <EmbeddedLayout>
      <SmsEditor />
    </EmbeddedLayout>
  );
}