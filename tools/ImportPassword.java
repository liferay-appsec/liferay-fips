package tools;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;

/**
 * Utility to store a JDBC password inside a BCFKS keystore using a
 * FIPS-approved algorithm (PBEWithHmacSHA512AndAES_256).
 *
 * Usage:
 *   java -cp .:<path-to-bc-fips-jar> tools.ImportPassword \
 *        <keystorePath> <storePassword> <alias> <entryPassword> <plainPassword>
 */
public class ImportPassword {

    public static void main(String[] args) throws Exception {
        if (args.length != 5) {
            System.err.println("Usage: java tools.ImportPassword <keystore> <storepass> <alias> <entrypass> <plaintext>");
            System.exit(1);
        }

        String keystorePath = args[0];
        char[] storepass = args[1].toCharArray();
        String alias = args[2];
        char[] entrypass = args[3].toCharArray();
        byte[] secretBytes = args[4].getBytes(StandardCharsets.UTF_8);

        KeyStore keyStore = KeyStore.getInstance("BCFKS", "BCFIPS");
        File ksFile = new File(keystorePath);

        if (ksFile.exists()) {
            try (FileInputStream in = new FileInputStream(ksFile)) {
                keyStore.load(in, storepass);
            }
        } else {
            keyStore.load(null, null);
        }

        SecretKey secretKey = new SecretKeySpec(secretBytes, "PBEWithHmacSHA512AndAES_256");
        KeyStore.ProtectionParameter protection =
                new KeyStore.PasswordProtection(entrypass);

        keyStore.setEntry(alias, new KeyStore.SecretKeyEntry(secretKey), protection);

        try (FileOutputStream out = new FileOutputStream(ksFile)) {
            keyStore.store(out, storepass);
        }

        System.out.printf("Stored alias '%s' in %s%n", alias, keystorePath);
    }
}
