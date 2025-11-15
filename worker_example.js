// Cloudflare Worker 示例代码
// 用于实现你的方案：通过 Worker + Lucky STUN 实现动态反向代理

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const pathParts = url.pathname.split('/').filter(p => p);
    
    // 提取第一个路径段（如 alist）
    if (pathParts.length === 0) {
      return new Response('No service specified', { status: 400 });
    }
    
    const serviceName = pathParts[0];
    const remainingPath = '/' + pathParts.slice(1).join('/');
    
    try {
      // 方案1: 使用 DNS over HTTPS 查询 TXT 记录
      // 或者使用 Cloudflare API（需要 env.API_TOKEN）
      let publicIP = null;
      let port = null;
      
      // 尝试从 Worker KV 缓存获取（如果配置了）
      if (env.STUN_CACHE) {
        const cached = await env.STUN_CACHE.get('stun_info');
        if (cached) {
          const info = JSON.parse(cached);
          publicIP = info.ip;
          port = info.port;
        }
      }
      
      // 如果缓存未命中，查询 DNS TXT 记录
      if (!publicIP || !port) {
        const dohUrl = `https://cloudflare-dns.com/dns-query?name=stun.abc.com&type=TXT`;
        const dohResponse = await fetch(dohUrl, {
          headers: {
            'Accept': 'application/dns-json'
          }
        });
        
        const dohData = await dohResponse.json();
        
        // 解析 TXT 记录，格式: "公网IP:端口" 或 "1.2.3.4:5678"
        if (dohData.Answer && dohData.Answer.length > 0) {
          const txtValue = dohData.Answer[0].data.replace(/"/g, '');
          const match = txtValue.match(/^(.+):(\d+)$/);
          if (match) {
            publicIP = match[1];
            port = match[2];
            
            // 缓存结果（TTL 60秒）
            if (env.STUN_CACHE) {
              await env.STUN_CACHE.put('stun_info', JSON.stringify({ip: publicIP, port: port}), {
                expirationTtl: 60
              });
            }
          }
        }
      }
      
      if (!publicIP || !port) {
        return new Response('Failed to get IP and port from TXT record', { status: 500 });
      }
      
      // 方案A: 直接使用 IP 地址（推荐，避免 DNS 解析问题）
      // 注意：使用 HTTP 而非 HTTPS，因为非标端口可能不支持 HTTPS
      const targetUrl = `http://${publicIP}:${port}${remainingPath}${url.search}`;
      
      // 方案B: 使用域名（需要确保 *.abc.com 的 A 记录关闭代理）
      // const targetUrl = `http://${serviceName}.abc.com:${port}${remainingPath}${url.search}`;
      
      // 构建请求，保留原始请求的头部（但需要调整 Host）
      const headers = new Headers(request.headers);
      // 设置正确的 Host 头，让 Lucky 的反向代理规则能正确匹配
      headers.set('Host', `${serviceName}.abc.com`);
      
      const targetRequest = new Request(targetUrl, {
        method: request.method,
        headers: headers,
        body: request.body
      });
      
      // 发起请求
      // 注意：如果使用 IP 地址，Lucky 的反向代理规则需要匹配 Host 头
      const response = await fetch(targetRequest, {
        // 可能需要设置超时
        // cf: {
        //   cacheTtl: 0
        // }
      });
      
      // 处理响应，可能需要调整 CORS 头部
      const newHeaders = new Headers(response.headers);
      newHeaders.set('Access-Control-Allow-Origin', '*');
      newHeaders.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
      
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: newHeaders
      });
      
    } catch (error) {
      return new Response(`Error: ${error.message}`, { 
        status: 500,
        headers: {
          'Content-Type': 'text/plain'
        }
      });
    }
  }
}

