import React from "react";
import { GetServerSideProps } from "next";
import EmbeddedLayout from "../../../../components/embeddedLayout";
import SegmentEditorV2 from "../../../../components/segments/editorV2";

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
      segmentId: id,
    },
  };
};

interface EmbeddedSegmentEditorProps {
  token: string;
  workspaceId: string;
  segmentId: string;
}

export default function EmbeddedSegmentEditor({ 
  token, 
  workspaceId, 
  segmentId 
}: EmbeddedSegmentEditorProps) {
  return (
    <EmbeddedLayout>
      <SegmentEditorV2 />
    </EmbeddedLayout>
  );
}