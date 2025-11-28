<%@ page import="java.security.Security" %>
<%@ page import="java.security.Provider" %>
<%@ page import="org.bouncycastle.crypto.fips.FipsStatus" %>
<%@ page contentType="text/html; charset=UTF-8" %>
<!DOCTYPE html>
<html>
<head>
    <title>Bouncy Castle FIPS Mode Verification</title>
    <style>
        body { font-family: sans-serif; margin: 2em; line-height: 1.6; }
        .success { color: green; font-weight: bold; }
        .error { color: red; font-weight: bold; }
        .info { color: navy; }
        code { background-color: #f0f0f0; padding: 2px 5px; border-radius: 4px; }
        .container { border: 1px solid #ccc; padding: 1em; border-radius: 8px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Bouncy Castle FIPS Verification</h1>
        <%
            String providerName = "BCFIPS";
            try {
                Provider fipsProvider = Security.getProvider(providerName);
                if (fipsProvider != null) {
                    out.println("<p class='success'>SUCCESS: The Bouncy Castle FIPS provider ('BCFIPS') is installed.</p>");
                    out.println("<p class='info'>Provider details: " + fipsProvider.getInfo() + "</p>");
                    boolean isFipsApprovedMode = FipsStatus.isReady();
                    if (isFipsApprovedMode) {
                        out.println("<p class='success'>SUCCESS: The provider is operating in FIPS approved-only mode.</p>");
                    } else {
                        out.println("<p class='error'>FAILURE: The provider is installed but is NOT in FIPS approved-only mode.</p>");
                    }
                } else {
                    out.println("<p class='error'>FAILURE: The Bouncy Castle FIPS provider ('BCFIPS') was NOT found.</p>");
                }
            } catch (NoClassDefFoundError e) {
                out.println("<p class='error'>CRITICAL FAILURE: A required Bouncy Castle class was not found.</p>");
            } catch (Throwable t) {
                out.println("<p class='error'>UNEXPECTED ERROR: " + t.getMessage() + "</p>");
            }
        %>
    </div>
</body>
</html>
