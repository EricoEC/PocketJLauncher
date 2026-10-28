package com.erico.pocketj.value.launcherprofiles;
import java.util.*;
import com.erico.pocketj.*;

public class MinecraftLauncherProfiles
{
	public Map<String, MinecraftProfile> profiles;
	public String clientToken;
	public Map<String, MinecraftAuthenticationDatabase> authenticationDatabase;
	// public Map launcherVersion;
	public MinecraftLauncherSettings settings;
	// public Map analyticsToken;
	public int analyticsFailcount;
	public MinecraftSelectedUser selectedUser;
    
    public String toJson() {
        return Tools.GLOBAL_GSON.toJson(this);
    }
}
