#!/usr/bin/env node

const http = require('http');
const httpProxy = require('http-proxy');
const fs = require('fs');
const yaml = require('js-yaml');
const { Minimatch } = require('minimatch');
const path = require('path');

const CONFIG_PATH = process.env.CONFIG_PATH || '/etc/restrictive-proxy.conf.j2';
const PORT = process.env.PORT || 8080;

// Load configuration
function loadConfig() {
  try {
    const configFile = fs.readFileSync(CONFIG_PATH, 'utf8');
    const config = yaml.load(configFile);

    // Replace password placeholders with environment variables
    if (config.proxy) {
      for (const [host, settings] of Object.entries(config.proxy)) {
        // Replace passwords in 'to' section (for outgoing auth)
        if (settings.to && settings.to.password && settings.to.password.startsWith('${') && settings.to.password.endsWith('}')) {
          const envVar = settings.to.password.slice(2, -1);
          settings.to.password = process.env[envVar] || settings.to.password;
        }
        // Replace passwords in 'auth' section (for incoming auth)
        if (settings.auth && settings.auth.password && settings.auth.password.startsWith('${') && settings.auth.password.endsWith('}')) {
          const envVar = settings.auth.password.slice(2, -1);
          settings.auth.password = process.env[envVar] || settings.auth.password;
        }
      }
    }

    return config;
  } catch (err) {
    console.error(`Failed to load config from ${CONFIG_PATH}:`, err.message);
    process.exit(1);
  }
}

// Check if path matches any pattern in the list
function matchesPattern(path, patterns) {
  if (!patterns || patterns.length === 0) {
    return false;
  }

  return patterns.some(pattern => {
    const matcher = new Minimatch(pattern);
    return matcher.match(path);
  });
}

// Check basic auth credentials
function checkBasicAuth(req, requiredUsername, requiredPassword) {
  const authHeader = req.headers['authorization'];
  if (!authHeader || !authHeader.startsWith('Basic ')) {
    return false;
  }

  const base64Credentials = authHeader.split(' ')[1];
  const credentials = Buffer.from(base64Credentials, 'base64').toString('utf-8');
  const [username, password] = credentials.split(':');

  return username === requiredUsername && password === requiredPassword;
}

// Check if request is allowed
function isRequestAllowed(method, path, restrictions, mode) {
  if (!restrictions) {
    return { allowed: true, matched: false };
  }

  const methodRestrictions = restrictions[method];
  if (!methodRestrictions) {
    return { allowed: mode === 'WATCH', matched: false };
  }

  const matched = matchesPattern(path, methodRestrictions);

  if (mode === 'RESTRICT') {
    return { allowed: matched, matched };
  } else {
    // WATCH mode - allow everything but log matches
    return { allowed: true, matched: matched };
  }
}

// Main proxy logic
function startProxy() {
  const config = loadConfig();

  if (!config.proxy) {
    console.error('No proxy configuration found');
    process.exit(1);
  }

  const proxies = {};

  // Create proxy instances for each target
  for (const [host, settings] of Object.entries(config.proxy)) {
    proxies[host] = {
      proxy: httpProxy.createProxyServer({}),
      settings: settings
    };
  }

  const server = http.createServer((req, res) => {
    // Strip port from host header if present
    const hostHeader = req.headers.host || '';
    const host = hostHeader.split(':')[0];

    if (!host || !proxies[host]) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Unknown host');
      return;
    }

    const { proxy, settings } = proxies[host];
    const { to, mode = 'WATCH', restrictions, auth } = settings;

    // Check basic auth if required
    if (auth && auth.username && auth.password) {
      if (!checkBasicAuth(req, auth.username, auth.password)) {
        console.log(`UNAUTHORIZED request to ${host}`);
        res.writeHead(401, {
          'Content-Type': 'text/plain',
          'WWW-Authenticate': 'Basic realm="Restrictive Proxy"'
        });
        res.end('Unauthorized');
        return;
      }
    }

    const method = req.method;
    const urlPath = req.url.split('?')[0];

    const { allowed, matched } = isRequestAllowed(method, urlPath, restrictions, mode);

    // Log the request
    if (!allowed) {
      console.log(`RESTRICTED ${method} ${urlPath}`);
      res.writeHead(403, { 'Content-Type': 'text/plain' });
      res.end('Forbidden: Access restricted by proxy policy');
      return;
    } else if (matched) {
      console.log(`ALLOWED ${method} ${urlPath}`);
    } else {
      console.log(`POTENTIALLY-DISALLOWED ${method} ${urlPath}`);
    }

    // Add basic auth if credentials are provided
    if (to.username && to.password) {
      const auth = Buffer.from(`${to.username}:${to.password}`).toString('base64');
      req.headers['authorization'] = `Basic ${auth}`;
    }

    // Proxy the request
    proxy.web(req, res, {
      target: to.url,
      changeOrigin: true,
      followRedirects: true
    }, (err) => {
      console.error(`Proxy error for ${method} ${urlPath}:`, err.message);
      if (!res.headersSent) {
        res.writeHead(502, { 'Content-Type': 'text/plain' });
        res.end('Bad Gateway');
      }
    });
  });

  server.listen(PORT, () => {
    console.log(`Restrictive proxy server running on port ${PORT}`);
    console.log(`Configuration loaded from ${CONFIG_PATH}`);
    console.log(`Configured hosts: ${Object.keys(proxies).join(', ')}`);
  });

  // Handle proxy errors
  Object.values(proxies).forEach(({ proxy }) => {
    proxy.on('error', (err, req, res) => {
      console.error('Proxy error:', err.message);
      if (res && !res.headersSent) {
        res.writeHead(502, { 'Content-Type': 'text/plain' });
        res.end('Bad Gateway');
      }
    });
  });
}

// Start the server
startProxy();
