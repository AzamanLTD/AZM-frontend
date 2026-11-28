# Files for azaman.me (app links)

These two files tell Android and iPhone that links on azaman.me belong to the
Azaman app, so a shared business, storefront, Susu invite or referral link
opens the app instead of the browser.

They must be reachable at exactly:

- `https://azaman.me/.well-known/assetlinks.json`
- `https://azaman.me/.well-known/apple-app-site-association` (no file extension)

Rules: served over HTTPS, no redirect, status 200. The Apple file should be
served as `application/json`.

## Uploading on Namecheap

If azaman.me uses Namecheap hosting (cPanel):

1. Open cPanel → File Manager → `public_html`.
2. Create a folder named `.well-known` (with the dot). Turn on "Show hidden
   files" in File Manager settings to see it.
3. Upload both files from this folder into `public_html/.well-known/`.
4. For the Apple file's content type, add this to `public_html/.well-known/.htaccess`:

   ```
   <Files "apple-app-site-association">
     ForceType application/json
   </Files>
   ```

5. Check in a browser: both URLs above should show the JSON.

If Namecheap only holds the domain (no hosting, or the domain forwards
somewhere), the files need a host that serves azaman.me; a forward/redirect
does not work for app links.

## Before uploading

- **Apple:** replace `APPLE_TEAM_ID` with your Apple Developer Team ID
  (developer.apple.com → Membership details), e.g. `AB12CD34EF.com.azaman.app`.
  The app's iOS bundle ID is now `com.azaman.app`, the same as on Firebase.
- **Android:** the fingerprint here is the one you gave (from Firebase). If the
  app is published with Play App Signing, also add the **app signing key**
  SHA-256 from Play Console → Test and release → App integrity → App signing;
  Google re-signs the app with that key, and links only verify against it.
  Add it as a second string in `sha256_cert_fingerprints`.

The paths here match the app's link handling (Android intent filters, iOS
associated domains, and the router's deep-link handling).
