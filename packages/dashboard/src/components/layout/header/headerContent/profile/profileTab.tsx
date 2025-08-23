// assets
import { Logout, Settings, SettingsApplications } from "@mui/icons-material";
import {
  List,
  ListItemButton,
  ListItemIcon,
  ListItemText,
} from "@mui/material";
// material-ui
import { useTheme } from "@mui/material/styles";
import Link from "next/link";
import { useRouter } from "next/router";

import { useAppStorePick } from "../../../../../lib/appStore";

// ==============================|| HEADER PROFILE - PROFILE TAB ||============================== //

function ProfileTab() {
  const theme = useTheme();
  const router = useRouter();
  const {
    signoutUrl,
    enableAdditionalDashboardSettings,
    additionalDashboardSettingsPath,
    additionalDashboardSettingsTitle,
    authMode,
  } = useAppStorePick([
    "signoutUrl",
    "enableAdditionalDashboardSettings",
    "additionalDashboardSettingsPath",
    "additionalDashboardSettingsTitle",
    "authMode",
  ]);

  const handleSignout = async (e: React.MouseEvent) => {
    if (authMode === "multi-tenant") {
      e.preventDefault();
      // Clear JWT from localStorage
      localStorage.removeItem("df-jwt");
      // Call signout endpoint
      await fetch("/api/auth/signout", { method: "POST" });
      // Redirect to login page
      router.push("/dashboard/auth/login");
    }
  };

  return (
    <List
      component="nav"
      sx={{
        p: 0,
        "& .MuiListItemIcon-root": {
          minWidth: 32,
          color: theme.palette.grey[500],
        },
      }}
    >
      <ListItemButton LinkComponent={Link} href="/settings">
        <ListItemIcon>
          <Settings />
        </ListItemIcon>
        <ListItemText primary="Settings" />
      </ListItemButton>
      {enableAdditionalDashboardSettings && additionalDashboardSettingsPath ? (
        <ListItemButton href={additionalDashboardSettingsPath}>
          <ListItemIcon>
            <SettingsApplications />
          </ListItemIcon>
          <ListItemText
            primary={additionalDashboardSettingsTitle ?? "Additional Settings"}
          />
        </ListItemButton>
      ) : null}
      {(signoutUrl || authMode === "multi-tenant") ? (
        <ListItemButton 
          href={signoutUrl || "/api/auth/signout"}
          onClick={authMode === "multi-tenant" ? handleSignout : undefined}
        >
          <ListItemIcon>
            <Logout />
          </ListItemIcon>
          <ListItemText primary="Sign Out" />
        </ListItemButton>
      ) : null}
    </List>
  );
}

export default ProfileTab;
