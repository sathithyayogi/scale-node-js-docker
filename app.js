const express = require('express');
const fs = require('fs').promises;
const path = require('path');
const app = express();
const port = process.env.PORT || 3000;

// Global cache for demonstration (will increase memory usage)
const requestCache = new Map();

// Ensure logs directory exists
const logsDir = path.join(__dirname, 'logs');
fs.mkdir(logsDir, { recursive: true }).catch(console.error);

// CPU-intensive function for demonstration
function simulateCPULoad() {
  const arr = [];
  for(let i = 0; i < 1000000; i++) {
    arr.push(Math.random().toString(36));
    if (i % 10000 === 0) {
      JSON.parse(JSON.stringify(arr));
    }
  }
  return arr.length;
}

// Memory-intensive function for demonstration
function simulateMemoryLoad() {
  const chunk = Buffer.alloc(1024 * 1024); // Allocate 1MB
  requestCache.set(Date.now(), chunk); // Store in global cache
  
  // Keep only last 10 entries (simple memory leak prevention)
  if (requestCache.size > 10) {
    const oldestKey = requestCache.keys().next().value;
    requestCache.delete(oldestKey);
  }
  
  return requestCache.size;
}

// Network-intensive function for demonstration
function generateLargeResponse() {
  const largeData = [];
  for(let i = 0; i < 1000; i++) {
    largeData.push({
      id: i,
      data: Buffer.from(Math.random().toString(36).repeat(100)).toString('base64'),
      timestamp: new Date().toISOString(),
      metrics: {
        cpu: process.cpuUsage(),
        memory: process.memoryUsage()
      }
    });
  }
  return largeData;
}

// Disk I/O intensive function for demonstration
async function simulateDiskIO() {
  const timestamp = Date.now();
  const logFile = path.join(logsDir, `request-${timestamp}.log`);
  
  // Write a large log file
  const logData = {
    timestamp: new Date().toISOString(),
    request: {
      headers: {},
      body: Buffer.from(Math.random().toString(36).repeat(1000)).toString('base64')
    },
    system: {
      memory: process.memoryUsage(),
      cpu: process.cpuUsage()
    }
  };

  await fs.writeFile(logFile, JSON.stringify(logData, null, 2));
  
  // Read all log files
  const files = await fs.readdir(logsDir);
  let totalSize = 0;
  
  // Keep only last 10 log files
  if (files.length > 10) {
    const oldestFiles = files.slice(0, files.length - 10);
    await Promise.all(oldestFiles.map(file => 
      fs.unlink(path.join(logsDir, file)).catch(console.error)
    ));
  }
  
  // Calculate total size of remaining logs
  for (const file of files) {
    const stats = await fs.stat(path.join(logsDir, file));
    totalSize += stats.size;
  }
  
  return {
    filesCount: files.length,
    totalSize: totalSize
  };
}

app.get('/health', async (req, res, next) => {
  try {
    // Add CPU, memory, and disk load
    const loadResult = simulateCPULoad();
    const memoryResult = simulateMemoryLoad();
    const networkResult = generateLargeResponse();
    const diskResult = await simulateDiskIO();
    
    res.json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      instance: process.env.HOSTNAME || 'local',
      metrics: {
        processMemory: process.memoryUsage(),
        cpuIntensive: loadResult,
        memoryIntensive: {
          cacheSize: memoryResult,
          cacheBytes: memoryResult * 1024 * 1024
        },
        networkIntensive: {
          responseSize: JSON.stringify(networkResult).length,
          items: networkResult
        },
        diskIntensive: diskResult
      }
    });
  } catch (err) {
    next(err);
  }
});

// Add error handling
app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(500).json({
    status: 'error',
    message: err.message
  });
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
}); 