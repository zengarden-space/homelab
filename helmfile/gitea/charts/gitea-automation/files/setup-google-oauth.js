const {chromium} = require('playwright');

const GITEA_URL = process.env.GITEA_URL || 'https://gitea.homelab.int.zengarden.space';
const ADMIN_USERNAME = process.env.GITEA_ADMIN_USERNAME || 'gitea_admin';
const ADMIN_PASSWORD = process.env.GITEA_ADMIN_PASSWORD;
const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;
const MAX_RETRIES = parseInt(process.env.MAX_RETRIES || '30');
const RETRY_DELAY = parseInt(process.env.RETRY_DELAY || '10000');

async function waitForGiteaReady() {
    console.log(`[wait] Waiting for Gitea to be ready at ${GITEA_URL}...`);

    for (let i = 0; i < MAX_RETRIES; i++) {
        try {
            const response = await fetch(GITEA_URL, {
                method: 'GET',
                headers: {'Accept': 'text/html'}
            });

            if (response.ok) {
                console.log(`[wait] ✓ Gitea is ready (HTTP ${response.status})`);
                return true;
            }

            console.log(`[wait] Attempt ${i + 1}/${MAX_RETRIES}: HTTP ${response.status}, retrying in ${RETRY_DELAY / 1000}s...`);
        } catch (error) {
            console.log(`[wait] Attempt ${i + 1}/${MAX_RETRIES}: ${error.message}, retrying in ${RETRY_DELAY / 1000}s...`);
        }

        await new Promise(resolve => setTimeout(resolve, RETRY_DELAY));
    }

    throw new Error(`Gitea did not become ready after ${MAX_RETRIES} attempts`);
}

async function setupGoogleOAuth() {
    console.log('[setup] Starting Gitea Google OAuth setup...');

    // Validate environment variables
    if (!ADMIN_PASSWORD) {
        throw new Error('GITEA_ADMIN_PASSWORD is required');
    }
    if (!GOOGLE_CLIENT_ID) {
        throw new Error('GOOGLE_CLIENT_ID is required');
    }
    if (!GOOGLE_CLIENT_SECRET) {
        throw new Error('GOOGLE_CLIENT_SECRET is required');
    }

    // Wait for Gitea to be ready
    await waitForGiteaReady();

    // Launch browser
    console.log('[browser] Launching Chromium...');
    const browser = await chromium.launch({
        headless: true,
        args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage']
    });

    try {
        const context = await browser.newContext({
            ignoreHTTPSErrors: true, // Accept self-signed certificates
            viewport: {width: 1280, height: 720}
        });

        const page = await context.newPage();

        // Navigate to login page
        console.log('[login] Navigating to login page...');
        await page.goto(`${GITEA_URL}/user/login`, {waitUntil: 'networkidle', timeout: 30000});

        // Fill in login credentials
        console.log('[login] Filling in admin credentials...');
        await page.fill('input[name="user_name"]', ADMIN_USERNAME);
        await page.fill('input[name="password"]', ADMIN_PASSWORD);

        // Submit login form
        console.log('[login] Submitting login form...');
        await page.click('button.ui.primary.button');

        // Wait for redirect after login
        await page.waitForURL(/\/(?!user\/login)/, {timeout: 30000});
        console.log('[login] ✓ Successfully logged in');

        // Navigate to site administration authentication sources page
        console.log('[admin] Navigating to authentication sources page...');
        await page.goto(`${GITEA_URL}/-/admin/auths`, {waitUntil: 'networkidle', timeout: 30000});

        // Check if Google OAuth already exists
        console.log('[check] Checking if Google OAuth source already exists...');
        const existingAuth = await page.locator('text=/Google OAuth/i').count();

        if (existingAuth > 0) {
            console.log('[check] ℹ Google OAuth authentication source already exists, skipping creation');
            return;
        }

        // Click "Add Authentication Source" button
        console.log('[create] Adding new authentication source...');
        await page.click('a[href*="/admin/auths/new"]');

        // Wait for the form to load
        await page.waitForSelector('.ui.selection.type.dropdown', {timeout: 10000});

        // Select OAuth2 authentication type using Semantic UI dropdown
        console.log('[create] Selecting OAuth2 authentication type...');
        await page.click('.ui.selection.type.dropdown');
        await page.click('.menu .item[data-value="6"]'); // OAuth2 is data-value="6"

        // Wait for OAuth2 provider dropdown to appear
        await page.waitForSelector('#oauth2_provider', {
            timeout: 5000,
            state: 'attached'
        });

        // Select Google as OAuth2 provider using Semantic UI dropdown
        console.log('[create] Selecting Google as OAuth2 provider...');
        await page.click('.ui.selection.type.dropdown:has(#oauth2_provider)');
        await page.click('.menu .item[data-value="gplus"]'); // Google is data-value="gplus"

        // Fill in authentication source details
        console.log('[create] Filling in OAuth configuration...');
        await page.fill('input#auth_name', 'Google OAuth');
        await page.fill('input#oauth2_key', GOOGLE_CLIENT_ID);
        await page.fill('input#oauth2_secret', GOOGLE_CLIENT_SECRET);

        // Enable the authentication source (it's already checked by default)
        // await page.check('input[name="is_active"]');

        // Take a screenshot for debugging
        await page.screenshot({path: '/tmp/gitea-oauth-form.png', fullPage: true});
        console.log('[debug] Screenshot saved to /tmp/gitea-oauth-form.png');

        // Submit the form
        console.log('[create] Submitting authentication source form...');
        await page.click('button.ui.primary.button');

        // Wait for redirect back to auth sources list
        await page.waitForURL(/\/admin\/auths$/, {timeout: 30000});

        // Verify the source was created
        const googleAuth = await page.locator('text=/Google OAuth/i').count();
        if (googleAuth > 0) {
            console.log('[create] ✓ Successfully created Google OAuth authentication source');
        } else {
            throw new Error('Google OAuth authentication source was not found after creation');
        }

        // Take final screenshot
        await page.screenshot({path: '/tmp/gitea-oauth-success.png', fullPage: true});
        console.log('[debug] Success screenshot saved to /tmp/gitea-oauth-success.png');

    } finally {
        await browser.close();
        console.log('[browser] Browser closed');
    }
}

// Main execution
(async () => {
    try {
        await setupGoogleOAuth();
        console.log('[done] ✓ Gitea Google OAuth setup completed successfully');
        process.exit(0);
    } catch (error) {
        console.error('[error] ✗ Failed to setup Google OAuth:', error.message);
        console.error(error.stack);
        process.exit(1);
    }
})();
