package com.erico.pocketj.value;
import com.erico.pocketj.*;
import java.io.*;
import com.google.gson.*;

public class MinecraftAccount
{
    public String accessToken = "0"; // access token
    public String clientToken = "0"; // clientID: refresh and invalidate
    public String profileId = "00000000-0000-0000-0000-000000000000"; // authenticate UUID
    public String username = "Steve";
    public String xuid;
    public String accountType;
    
    public String save(String outPath) throws IOException {
        Tools.write(outPath, Tools.GLOBAL_GSON.toJson(this));
        return outPath;
    }
    
    public String save() throws IOException {
        return save(Tools.DIR_ACCOUNT_NEW + "/" + username + ".json");
    }
    
    public static MinecraftAccount parse(String content) throws JsonSyntaxException {
        MinecraftAccount account = Tools.GLOBAL_GSON.fromJson(content, MinecraftAccount.class);
        // Read access token from keychain
        if (account.xuid != null) {
            account.accessToken = getAccessTokenFromKeychain(account.xuid);
        }
        // The Yggdrasil keychain identity is not an Xbox user ID and must not
        // be forwarded to Minecraft's --xuid argument.
        if ("yggdrasil".equals(account.accountType)) account.xuid = "0";
        return account;
    }
    
    public static MinecraftAccount load(String name) throws IOException, JsonSyntaxException {
        MinecraftAccount acc = parse(Tools.read(Tools.DIR_ACCOUNT_NEW + "/" + name + ".json"));
        if (acc.accessToken == null) {
            acc.accessToken = "0";
        } if (acc.clientToken == null) {
            acc.clientToken = "0";
        } if (acc.profileId == null) {
            acc.profileId = "0";
        } if (acc.username == null) {
            acc.username = "0";
        } if (acc.xuid == null) {
            acc.xuid = "0";
        }
        return acc;
    }

    static {
        System.loadLibrary("PocketJAccountJNI");
    }
    public static native String getAccessTokenFromKeychain(String xuid);
}
