const express = require('express');
const axios = require('axios');
const path = require('path');
const fs = require('fs');
const { JSDOM } = require('jsdom');

const app = express();
const PORT = process.env.PORT || 7001;

// 配置文件路径
const CONFIG_FILE = path.join(__dirname, 'addon-config.json');

// 默认配置
const DEFAULT_CONFIG = {
    alist_url: 'http://localhost:5244',
    search_url: 'http://localhost:5244',
    container_type: 'alist',
    alist_token: '',
    container_name: ''
};

// 读取配置文件
function loadConfig() {
    try {
        if (fs.existsSync(CONFIG_FILE)) {
            const fileConfig = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
            console.log('从配置文件加载配置:', CONFIG_FILE);
            return fileConfig;
        }
    } catch (error) {
        console.error('读取配置文件失败:', error.message);
    }
    return {};
}

// 保存配置文件
function saveConfig(config) {
    try {
        fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));
        console.log('配置已保存到文件:', CONFIG_FILE);
        return true;
    } catch (error) {
        console.error('保存配置文件失败:', error.message);
        return false;
    }
}

// 获取最终配置（优先级：环境变量 > 配置文件 > 默认值）
function getFinalConfig() {
    const fileConfig = loadConfig();

    return {
        alist_url: process.env.ALIST_URL || fileConfig.alist_url || DEFAULT_CONFIG.alist_url,
        search_url: process.env.SEARCH_URL || fileConfig.search_url || DEFAULT_CONFIG.search_url,
        container_type: process.env.CONTAINER_TYPE || fileConfig.container_type || DEFAULT_CONFIG.container_type,
        alist_token: process.env.ALIST_TOKEN || fileConfig.alist_token || DEFAULT_CONFIG.alist_token,
        container_name: process.env.CONTAINER_NAME || fileConfig.container_name || DEFAULT_CONFIG.container_name
    };
}

// 全局配置
const CONFIG = getFinalConfig();

// 兼容性：保持原有的常量名
const ALIST_URL = CONFIG.alist_url;
const SEARCH_URL = CONFIG.search_url;
const ALIST_TOKEN = CONFIG.alist_token;
const CONTAINER_TYPE = CONFIG.container_type;
const CONTAINER_NAME = CONFIG.container_name;

// 插件manifest
app.get('/manifest.json', (req, res) => {
    res.json({
        id: 'org.alist.gbox.addon',
        version: '2.0.0',
        name: 'AList G-Box Addon Enhanced',
        description: 'Stream from AList with enhanced search, douban to IMDB conversion, and smart container detection',
        resources: ['catalog', 'stream', 'meta'],
        types: ['movie', 'series'],
        catalogs: [
            {
                type: 'movie',
                id: 'gbox-alist-movies',
                name: 'G-Box AList Movies',
                extra: [
                    {
                        name: 'search',
                        isRequired: false
                    }
                ]
            },
            {
                type: 'series',
                id: 'gbox-alist-series',
                name: 'G-Box AList Series',
                extra: [
                    {
                        name: 'search',
                        isRequired: false
                    }
                ]
            }
        ],
        idPrefixes: ['alist:', 'tt'],  // 支持 alist ID 和 IMDB ID
        behaviorHints: {
            adult: false,
            p2p: false,
            configurable: true,
            configurationRequired: true
        },
        config: [
            {
                key: 'alist_url',
                type: 'text',
                title: 'AList URL',
                default: ALIST_URL
            },
            {
                key: 'search_url',
                type: 'text',
                title: 'Search URL',
                default: SEARCH_URL
            },
            {
                key: 'container_type',
                type: 'select',
                title: 'Container Type',
                options: ['gbox', 'alist'],
                default: CONTAINER_TYPE
            },
            {
                key: 'alist_token',
                type: 'password',
                title: 'AList Token (Required)',
                default: '',
                required: true
            }
        ]
    });
});

// 配置化的manifest（支持用户自定义配置）
app.get('/:config/manifest.json', (req, res) => {
    const config = req.params.config;

    // 解析配置参数
    const configParams = {};
    if (config && config !== 'configure') {
        try {
            const decoded = Buffer.from(config, 'base64').toString();
            const params = new URLSearchParams(decoded);
            configParams.alist_url = params.get('alist_url') || ALIST_URL;
            configParams.search_url = params.get('search_url') || SEARCH_URL;
            configParams.container_type = params.get('container_type') || CONTAINER_TYPE;
            configParams.alist_token = params.get('alist_token') || '';
        } catch (error) {
            console.error('解析配置参数失败:', error);
        }
    }

    res.json({
        id: 'org.alist.gbox.addon',
        version: '2.0.0',
        name: `AList G-Box Addon Enhanced (${configParams.container_type || CONTAINER_TYPE})`,
        description: 'Stream from AList with enhanced search, douban to IMDB conversion, and smart container detection',
        resources: ['catalog', 'stream', 'meta'],
        types: ['movie', 'series'],
        catalogs: [
            {
                type: 'movie',
                id: 'gbox-alist-movies',
                name: 'G-Box AList Movies',
                extra: [
                    {
                        name: 'search',
                        isRequired: false
                    }
                ]
            },
            {
                type: 'series',
                id: 'gbox-alist-series',
                name: 'G-Box AList Series',
                extra: [
                    {
                        name: 'search',
                        isRequired: false
                    }
                ]
            }
        ],
        idPrefixes: ['alist:', 'tt'],
        behaviorHints: {
            adult: false,
            p2p: false,
            configurable: true,
            configurationRequired: false
        }
    });
});

// 目录浏览端点 - 无搜索关键词时显示热门内容
app.get('/catalog/:type/:id.json', async (req, res) => {
    try {
        const { type, id } = req.params;
        console.log(`目录浏览请求: type=${type}, id=${id}`);

        // 获取热门内容（从索引文件中获取前20个）
        const popularResults = await getPopularContent(type);

        // 转换为Stremio格式
        const metas = popularResults.map(item => convertToStremioMetaSync(item, type));

        res.json({
            metas: metas.slice(0, 20) // 限制返回数量
        });

    } catch (error) {
        console.error('目录浏览错误:', error);
        res.json({ metas: [] });
    }
});

// 目录搜索端点 - 这是关键！
app.get('/catalog/:type/:id/search=:query.json', async (req, res) => {
    try {
        const { type, id, query } = req.params;
        console.log(`搜索请求: type=${type}, id=${id}, query=${query}`);

        // 优先从索引文件搜索，如果没有索引文件则调用G-Box API
        const searchResults = await searchContent(query, type);

        // 转换为Stremio格式
        const metas = searchResults.map(item => convertToStremioMetaSync(item, type));

        res.json({
            metas: metas.slice(0, 20) // 限制返回数量
        });

    } catch (error) {
        console.error('搜索错误:', error);
        res.json({ metas: [] });
    }
});

// 配置更新端点
app.post('/configure', express.json(), (req, res) => {
    try {
        const newConfig = req.body;
        console.log('收到配置更新请求:', newConfig);

        // 验证配置
        const validConfig = {};
        if (newConfig.alist_url) validConfig.alist_url = newConfig.alist_url;
        if (newConfig.search_url) validConfig.search_url = newConfig.search_url;
        if (newConfig.container_type && ['gbox', 'alist'].includes(newConfig.container_type)) {
            validConfig.container_type = newConfig.container_type;
        }
        if (newConfig.alist_token !== undefined) validConfig.alist_token = newConfig.alist_token;
        if (newConfig.container_name) validConfig.container_name = newConfig.container_name;

        // 保存配置
        if (saveConfig(validConfig)) {
            // 更新全局配置
            Object.assign(CONFIG, validConfig);

            res.json({
                success: true,
                message: '配置更新成功',
                config: validConfig
            });
        } else {
            res.status(500).json({
                success: false,
                message: '配置保存失败'
            });
        }

    } catch (error) {
        console.error('配置更新失败:', error);
        res.status(400).json({
            success: false,
            message: '配置格式错误'
        });
    }
});

// 获取当前配置端点
app.get('/configure', (req, res) => {
    res.json({
        success: true,
        config: CONFIG
    });
});

// 流媒体端点 - 处理播放
app.get('/stream/:type/:id.json', async (req, res) => {
    try {
        const { type, id } = req.params;
        console.log(`流媒体请求: type=${type}, id=${id}`);

        // 解析AList ID
        const alistInfo = parseAlistId(id);
        if (!alistInfo) {
            return res.json({ streams: [] });
        }

        // 获取播放流
        const streams = await getAlistStreams(alistInfo, type);

        res.json({ streams });

    } catch (error) {
        console.error('获取流媒体错误:', error);
        res.json({ streams: [] });
    }
});

// 新增：元数据端点 - 支持豆瓣ID到IMDB ID转换和关键词猜测
app.get('/meta/:type/:id.json', async (req, res) => {
    try {
        const { type, id } = req.params;
        console.log(`元数据请求: type=${type}, id=${id}`);

        // 解析AList ID
        const alistInfo = parseAlistId(id);
        if (!alistInfo) {
            return res.json({ meta: null });
        }

        let meta = {
            id: id,
            type: type,
            name: '未知标题',
            poster: 'https://via.placeholder.com/300x450/333333/ffffff?text=No+Poster'
        };

        if (alistInfo.originalVodId.startsWith('gbox$')) {
            // 情况A：G-Box容器，尝试从豆瓣ID转换
            const doubanId = extractDoubanIdFromAlistInfo(alistInfo);

            if (doubanId) {
                console.log(`尝试转换豆瓣ID ${doubanId} 为 IMDB ID`);
                const imdbId = await getImdbIdFromDouban(doubanId);

                if (imdbId) {
                    console.log(`成功转换为 IMDB ID: ${imdbId}`);
                    // 重定向到IMDB ID对应的元数据
                    meta.id = imdbId;
                    meta.imdb_id = imdbId;
                    meta.douban_id = doubanId;
                }
            }
        } else if (alistInfo.originalVodId.startsWith('alist$')) {
            // 情况B：普通alist，尝试通过关键词猜测
            // 这里我们不做复杂的猜测，让Stremio自己处理
            console.log('普通alist结果，使用默认元数据处理');
            meta.poster = 'https://via.placeholder.com/300x450/666666/ffffff?text=AList';
        }

        res.json({ meta });

    } catch (error) {
        console.error('获取元数据错误:', error);
        res.json({ meta: null });
    }
});

// 获取热门内容（根据安装时配置的容器类型获取）
async function getPopularContent(type = 'movie') {
    try {
        // 检查 token 配置
        if (!checkAlistToken()) {
            console.error('AList Token 未配置，返回空的热门内容');
            return [];
        }

        if (CONTAINER_TYPE === 'gbox') {
            // 情况A：从G-Box容器获取热门内容
            console.log('从G-Box容器获取热门内容');
            return await searchGBoxDirect('', type); // 空搜索获取默认内容
        } else {
            // 情况B：从普通alist获取热门内容（使用常见关键词）
            console.log('从普通alist获取热门内容');
            const popularKeywords = type === 'series' ? ['电视剧', '剧集'] : ['电影', '影片'];
            const results = [];

            for (const keyword of popularKeywords) {
                const searchResults = await searchAlistNormal(keyword, type);
                results.push(...searchResults.slice(0, 10)); // 每个关键词取10个
                if (results.length >= 20) break;
            }

            return results.slice(0, 20);
        }

    } catch (error) {
        console.error('获取热门内容失败:', error);
        return [];
    }
}

// 检查 AList Token 是否配置
function checkAlistToken() {
    if (!ALIST_TOKEN || ALIST_TOKEN.trim() === '') {
        console.error('AList Token 未配置，无法调用 AList API');
        return false;
    }
    return true;
}

// 搜索内容（根据安装时配置的容器类型选择搜索方式）
async function searchContent(keyword, type = 'movie') {
    try {
        // 检查 token 配置
        if (!checkAlistToken()) {
            console.error('AList Token 未配置，返回空结果');
            return [];
        }

        if (CONTAINER_TYPE === 'gbox') {
            // 情况A：G-Box容器，调用5678端口的search API
            console.log('使用G-Box容器内置搜索 API');
            return await searchGBoxDirect(keyword, type);
        } else {
            // 情况B：普通alist容器，调用/api/fs/search API
            console.log('使用普通alist搜索 API');
            return await searchAlistNormal(keyword, type);
        }

    } catch (error) {
        console.error('搜索内容失败:', error);
        return [];
    }
}

// 解析配置参数
function parseConfigParams(config) {
    const defaultParams = {
        alist_url: ALIST_URL,
        search_url: SEARCH_URL,
        container_type: CONTAINER_TYPE,
        alist_token: ALIST_TOKEN
    };

    if (!config || config === 'configure') {
        return defaultParams;
    }

    try {
        const decoded = Buffer.from(config, 'base64').toString();
        const params = new URLSearchParams(decoded);

        return {
            alist_url: params.get('alist_url') || defaultParams.alist_url,
            search_url: params.get('search_url') || defaultParams.search_url,
            container_type: params.get('container_type') || defaultParams.container_type,
            alist_token: params.get('alist_token') || defaultParams.alist_token
        };
    } catch (error) {
        console.error('解析配置参数失败:', error);
        return defaultParams;
    }
}

// 使用配置参数的搜索函数
async function searchContentWithConfig(keyword, type, configParams) {
    try {
        if (configParams.container_type === 'gbox') {
            return await searchGBoxDirectWithConfig(keyword, type, configParams);
        } else {
            return await searchAlistNormalWithConfig(keyword, type, configParams);
        }
    } catch (error) {
        console.error('配置化搜索失败:', error);
        return [];
    }
}

// 使用配置参数的热门内容获取
async function getPopularContentWithConfig(type, configParams) {
    try {
        if (configParams.container_type === 'gbox') {
            return await searchGBoxDirectWithConfig('', type, configParams);
        } else {
            const popularKeywords = type === 'series' ? ['电视剧', '剧集'] : ['电影', '影片'];
            const results = [];

            for (const keyword of popularKeywords) {
                const searchResults = await searchAlistNormalWithConfig(keyword, type, configParams);
                results.push(...searchResults.slice(0, 10));
                if (results.length >= 20) break;
            }

            return results.slice(0, 20);
        }
    } catch (error) {
        console.error('配置化热门内容获取失败:', error);
        return [];
    }
}

// 注意：已移除索引文件相关函数，现在只支持两种搜索方式：
// 情况A：G-Box容器调用5678端口搜索API
// 情况B：普通alist容器调用/api/fs/search API

// 判断是否为媒体文件
function isMediaFileByPath(filePath) {
    const mediaExtensions = ['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.3gp', '.ts', '.m2ts'];
    const ext = path.extname(filePath).toLowerCase();
    return mediaExtensions.includes(ext);
}

// 配置化的G-Box搜索函数
async function searchGBoxDirectWithConfig(keyword, type = 'movie', configParams) {
    try {
        const url = `${configParams.search_url}/search`;
        const params = {
            box: encodeURIComponent(keyword),
            url: '',
            type: 'video',
            call: 'strem-gbox'
        };

        console.log(`调用配置化G-Box搜索API: ${url}`, params);

        const headers = {};
        if (configParams.alist_token) {
            headers['Authorization'] = configParams.alist_token;
        }

        const response = await axios.get(url, {
            params,
            headers,
            timeout: 10000
        });

        if (response.data && response.data.results) {
            return response.data.results.map(item => convertGBoxResultToVodFormat(item, type));
        }

        return [];

    } catch (error) {
        console.error('配置化G-Box搜索失败:', error.message);
        return [];
    }
}

// 配置化的普通alist搜索函数
async function searchAlistNormalWithConfig(keyword, type = 'movie', configParams) {
    try {
        const url = `${configParams.alist_url}/api/fs/search`;
        const requestData = {
            parent: "/",
            keywords: keyword,
            scope: 0,
            page: 1,
            per_page: 20
        };

        console.log(`调用配置化alist搜索API: ${url}`, requestData);

        const headers = {
            'Content-Type': 'application/json'
        };
        if (configParams.alist_token) {
            headers['Authorization'] = configParams.alist_token;
        }

        const response = await axios.post(url, requestData, {
            headers,
            timeout: 10000
        });

        if (response.data && response.data.code === 200 && response.data.data && response.data.data.content) {
            return response.data.data.content.map(item => convertAlistNormalResultToVodFormat(item, keyword, type));
        }

        return [];

    } catch (error) {
        console.error('配置化alist搜索失败:', error.message);
        return [];
    }
}

// 情况A：G-Box容器直接搜索（调用5678端口）
async function searchGBoxDirect(keyword, type = 'movie') {
    try {
        // 调用G-Box容器内置的搜索API
        const url = `${SEARCH_URL}/search`;
        const params = {
            box: encodeURIComponent(keyword),
            url: '',
            type: 'video',
            call: 'strem-gbox'  // 特殊标识，让 search 脚本返回 JSON
        };

        console.log(`调用G-Box容器搜索API: ${url}`, params);

        const headers = {};
        if (ALIST_TOKEN) {
            headers['Authorization'] = ALIST_TOKEN;
        }

        const response = await axios.get(url, {
            params,
            headers,
            timeout: 10000
        });

        console.log(`G-Box容器搜索响应:`, response.data);

        if (response.data && response.data.results) {
            // 转换为 VOD 格式（情况A有完整的豆瓣信息）
            return response.data.results.map(item => convertGBoxResultToVodFormat(item, type));
        }

        return [];

    } catch (error) {
        console.error('G-Box容器搜索失败:', error.message);
        if (error.response) {
            console.error('响应状态:', error.response.status);
            console.error('响应数据:', error.response.data);
        }
        return [];
    }
}

// 将G-Box搜索结果转换为VOD格式（情况A）
function convertGBoxResultToVodFormat(item, type) {
    // item 格式: { path, title, doubanId, rating, posterUrl, year, region, genres }
    const isMediaFile = isMediaFileByPath(item.path);
    const vodId = `gbox$${encodeURIComponent(item.path)}$1`;

    return {
        vod_id: vodId,
        vod_name: item.title,
        vod_pic: item.posterUrl || 'https://via.placeholder.com/300x450/333333/ffffff?text=No+Poster',
        vod_content: `${item.path}#${item.title}#${item.doubanId}#${item.rating}#${item.posterUrl}#${item.year}#${item.region}#${item.genres}`,
        vod_remarks: item.genres,
        vod_tag: isMediaFile ? 'FILE' : 'FOLDER',
        douban_id: item.doubanId  // 保存豆瓣ID用于后续转换
    };
}

// 情况B：普通alist搜索（调用/api/fs/search）
async function searchAlistNormal(keyword, type = 'movie') {
    try {
        // 调用普通alist的搜索API
        const url = `${ALIST_URL}/api/fs/search`;
        const requestData = {
            parent: "/",
            keywords: keyword,
            scope: 0,
            page: 1,
            per_page: 20
        };

        console.log(`调用普通alist搜索API: ${url}`, requestData);

        const headers = {
            'Content-Type': 'application/json'
        };
        if (ALIST_TOKEN) {
            headers['Authorization'] = ALIST_TOKEN;
        }

        const response = await axios.post(url, requestData, {
            headers,
            timeout: 10000
        });

        console.log(`普通alist搜索响应:`, response.data);

        if (response.data && response.data.code === 200 && response.data.data && response.data.data.content) {
            // 转换为 VOD 格式（情况B需要猜测IMDB ID）
            return response.data.data.content.map(item => convertAlistNormalResultToVodFormat(item, keyword, type));
        }

        return [];

    } catch (error) {
        console.error('普通alist搜索失败:', error.message);
        if (error.response) {
            console.error('响应状态:', error.response.status);
            console.error('响应数据:', error.response.data);
        }
        return [];
    }
}

// 将普通alist搜索结果转换为VOD格式（情况B）
function convertAlistNormalResultToVodFormat(item, keyword, type) {
    // item 格式: { parent, name, is_dir, size, type }
    const fullPath = `${item.parent}/${item.name}`.replace('//', '/');
    const vodId = `alist$${encodeURIComponent(fullPath)}$1`;

    // 拼接父目录和文件名作为显示名称
    const displayName = fullPath;

    return {
        vod_id: vodId,
        vod_name: displayName,
        vod_pic: 'https://via.placeholder.com/300x450/666666/ffffff?text=AList', // 固定海报图
        vod_content: fullPath,
        vod_remarks: item.is_dir ? 'FOLDER' : 'FILE',
        vod_tag: item.is_dir ? 'FOLDER' : 'FILE',
        search_keyword: keyword,  // 保存搜索关键词用于猜测IMDB ID
        file_size: item.size
    };
}

// 注意：已移除旧的G-Box API搜索函数，现在使用直接搜索方式

// 注意：已移除异步版本的转换函数，现在只使用同步版本

// 同步版本的转换函数（用于不需要异步转换的场景）
function convertToStremioMetaSync(item, type) {
    const meta = {
        id: `alist:${item.vod_id}`,
        type: type,
        name: item.vod_name,
        poster: extractPoster(item),
        description: item.vod_content || '',
        genres: extractGenres(item),
        year: extractYear(item)
    };

    // 检查是否为G-Box结果（情况A）还是普通alist结果（情况B）
    if (item.vod_id.startsWith('gbox$')) {
        // 情况A：G-Box容器结果，有完整的豆瓣信息
        if (item.vod_content && item.vod_content.includes('#')) {
            const indexData = parseIndexData(item.vod_content);
            if (indexData) {
                meta.poster = indexData.posterUrl || meta.poster;

                // 处理可选的年份字段
                if (indexData.year && indexData.year.trim()) {
                    const year = parseInt(indexData.year);
                    if (!isNaN(year)) {
                        meta.year = year;
                    }
                }

                // 处理可选的类型字段
                if (indexData.genres && indexData.genres.trim()) {
                    meta.genres = indexData.genres.split('/').filter(g => g.trim());
                }

                // 处理评分
                if (indexData.rating && indexData.rating.trim()) {
                    meta.imdbRating = indexData.rating;
                }

                // 处理可选的地区字段
                if (indexData.region && indexData.region.trim()) {
                    meta.country = indexData.region;
                }

                // 保存豆瓣ID
                if (indexData.doubanId && indexData.doubanId.trim()) {
                    meta.doubanId = indexData.doubanId;
                }
            }
        }

        // 如果直接有豆瓣ID字段
        if (item.douban_id) {
            meta.doubanId = item.douban_id;
        }
    } else if (item.vod_id.startsWith('alist$')) {
        // 情况B：普通alist结果，使用固定海报图和搜索关键词
        meta.poster = 'https://via.placeholder.com/300x450/666666/ffffff?text=AList';
        meta.description = `文件路径: ${item.vod_content}`;

        // 保存搜索关键词用于后续猜测IMDB ID
        if (item.search_keyword) {
            meta.searchKeyword = item.search_keyword;
        }

        // 如果有文件大小信息
        if (item.file_size) {
            meta.description += `\n文件大小: ${formatFileSize(item.file_size)}`;
        }

        // 设置默认类型
        meta.genres = [item.vod_remarks || 'Unknown'];
    }

    return meta;
}

// 解析索引数据
function parseIndexData(content) {
    try {
        // 索引格式: ./path#title#doubanId#rating#posterUrl[#year#region#genres]
        // 前5个字段是必须的，后3个字段是可选的
        const parts = content.split('#');
        if (parts.length >= 5) {
            return {
                path: parts[0],
                title: parts[1],
                doubanId: parts[2],
                rating: parts[3],
                posterUrl: parts[4],
                year: parts[5] || '',        // 可选字段
                region: parts[6] || '',      // 可选字段
                genres: parts[7] || ''       // 可选字段
            };
        }
    } catch (error) {
        console.error('解析索引数据失败:', error);
    }
    return null;
}

// 提取海报URL
function extractPoster(item) {
    if (item.vod_pic && item.vod_pic !== 'https://pic.stackoverflow.wiki/uploadImages/122/140/12/253/2023/08/28/19/28/49/e0c2c4dc-9559-4a8e-9d8c-063b5b50cbc7.png') {
        return item.vod_pic;
    }
    
    // 尝试从索引数据中提取
    const indexData = parseIndexData(item.vod_content);
    if (indexData && indexData.posterUrl) {
        return indexData.posterUrl;
    }
    
    // 返回默认海报
    return 'https://via.placeholder.com/300x450/333333/ffffff?text=No+Poster';
}

// 提取类型
function extractGenres(item) {
    const indexData = parseIndexData(item.vod_content);
    if (indexData && indexData.genres && indexData.genres.trim()) {
        return indexData.genres.split('/').filter(g => g.trim());
    }

    // 根据vod_remarks尝试提取
    if (item.vod_remarks) {
        return [item.vod_remarks];
    }

    return [];
}

// 提取年份
function extractYear(item) {
    const indexData = parseIndexData(item.vod_content);
    if (indexData && indexData.year && indexData.year.trim()) {
        const year = parseInt(indexData.year);
        if (!isNaN(year) && year > 1900 && year <= new Date().getFullYear() + 5) {
            return year;
        }
    }

    // 尝试从名称中提取年份
    const yearMatch = item.vod_name.match(/\((\d{4})\)/);
    if (yearMatch) {
        const year = parseInt(yearMatch[1]);
        if (year > 1900 && year <= new Date().getFullYear() + 5) {
            return year;
        }
    }

    return null;
}

// 解析AList ID
function parseAlistId(id) {
    try {
        // ID格式: alist:siteId$encodedPath$1 或 alist:index$encodedPath$1
        if (!id.startsWith('alist:')) {
            return null;
        }

        const vodId = id.substring(6); // 去掉 'alist:' 前缀
        const parts = vodId.split('$');

        if (parts.length >= 2) {
            return {
                siteId: parts[0],
                encodedPath: parts[1],
                index: parts[2] || '1',
                originalVodId: vodId,
                isFromIndex: parts[0] === 'index', // 标记是否来自索引文件
                isFromAlist: parts[0] === 'alist'  // 标记是否来自直接alist搜索
            };
        }

        return null;
    } catch (error) {
        console.error('解析AList ID失败:', error);
        return null;
    }
}

// 从 alistInfo 中提取豆瓣ID
function extractDoubanIdFromAlistInfo(alistInfo) {
    try {
        // 解码路径，查找是否包含豆瓣ID信息
        const decodedPath = decodeURIComponent(alistInfo.encodedPath);

        // 如果路径包含索引信息格式: path#title#doubanId#...
        if (decodedPath.includes('#')) {
            const parts = decodedPath.split('#');
            if (parts.length >= 3) {
                const doubanId = parts[2];
                if (doubanId && doubanId !== '0' && /^\d+$/.test(doubanId)) {
                    return doubanId;
                }
            }
        }

        return null;
    } catch (error) {
        console.error('提取豆瓣ID失败:', error);
        return null;
    }
}

// 获取AList流媒体
async function getAlistStreams(alistInfo, type = 'movie') {
    try {
        // 根据ID前缀判断来源并选择处理方式
        if (alistInfo.originalVodId.startsWith('gbox$') || alistInfo.originalVodId.startsWith('alist$')) {
            // 来自新的搜索结果
            return await getStreamsFromAlist(alistInfo, type);
        } else {
            // 兼容旧格式（如果有的话）
            return await getStreamsFromGBox(alistInfo);
        }
    } catch (error) {
        console.error('获取流媒体失败:', error);
        return [];
    }
}

// 从 alist 获取流媒体（支持电影和剧集）
async function getStreamsFromAlist(alistInfo, type = 'movie') {
    try {
        const filePath = decodeURIComponent(alistInfo.encodedPath);
        console.log(`从 alist 获取流媒体: ${filePath}, 类型: ${type}`);

        // 判断是文件还是目录
        const isMediaFile = isMediaFileByPath(filePath);

        if (isMediaFile) {
            // 直接是媒体文件
            return [{
                url: `${ALIST_URL}/d/${filePath}`,
                title: path.basename(filePath),
                quality: getQualityFromName(filePath)
            }];
        } else {
            // 是目录，需要调用 alist API 获取文件列表
            return await getPlaylistFromAlist(filePath, type);
        }

    } catch (error) {
        console.error('从 alist 获取流媒体失败:', error);
        return [];
    }
}

// 从 alist API 获取播放列表
async function getPlaylistFromAlist(dirPath, type) {
    try {
        const url = `${ALIST_URL}/api/fs/list`;
        const requestData = {
            path: dirPath,
            password: '',
            page: 1,
            per_page: 100
        };

        console.log(`调用 alist API 获取目录列表: ${url}`, requestData);

        const headers = {
            'Content-Type': 'application/json'
        };
        if (ALIST_TOKEN) {
            headers['Authorization'] = `Bearer ${ALIST_TOKEN}`;
        }

        const response = await axios.post(url, requestData, {
            headers,
            timeout: 10000
        });

        if (response.data && response.data.code === 200 && response.data.data && response.data.data.content) {
            const files = response.data.data.content
                .filter(file => !file.is_dir && isMediaFormat(file.name))
                .sort((a, b) => a.name.localeCompare(b.name));

            if (type === 'series') {
                // 剧集格式：按季和集分组
                return formatSeriesStreams(files, dirPath);
            } else {
                // 电影格式：简单列表
                return formatMovieStreams(files, dirPath);
            }
        }

        return [];

    } catch (error) {
        console.error('获取 alist 播放列表失败:', error);
        return [];
    }
}

// 格式化电影流媒体
function formatMovieStreams(files, dirPath) {
    return files.map(file => ({
        url: `${ALIST_URL}/d${dirPath}/${file.name}`,
        title: file.name,
        quality: getQualityFromName(file.name),
        size: file.size ? formatFileSize(file.size) : undefined
    }));
}

// 格式化剧集流媒体
function formatSeriesStreams(files, dirPath) {
    // 尝试按季分组
    const seasons = {};

    files.forEach(file => {
        // 尝试从文件名中提取季和集信息
        const seasonMatch = file.name.match(/[Ss](\d+)[Ee](\d+)/);
        if (seasonMatch) {
            const season = parseInt(seasonMatch[1]);
            const episode = parseInt(seasonMatch[2]);

            if (!seasons[season]) {
                seasons[season] = [];
            }

            seasons[season].push({
                url: `${ALIST_URL}/d${dirPath}/${file.name}`,
                title: `S${season.toString().padStart(2, '0')}E${episode.toString().padStart(2, '0')} - ${file.name}`,
                quality: getQualityFromName(file.name),
                size: file.size ? formatFileSize(file.size) : undefined,
                season: season,
                episode: episode
            });
        } else {
            // 无法识别季集信息，放入默认季
            if (!seasons[1]) {
                seasons[1] = [];
            }

            seasons[1].push({
                url: `${ALIST_URL}/d${dirPath}/${file.name}`,
                title: file.name,
                quality: getQualityFromName(file.name),
                size: file.size ? formatFileSize(file.size) : undefined,
                season: 1,
                episode: seasons[1].length + 1
            });
        }
    });

    // 将分组后的结果展平，按季和集排序
    const result = [];
    Object.keys(seasons).sort((a, b) => parseInt(a) - parseInt(b)).forEach(season => {
        seasons[season].sort((a, b) => a.episode - b.episode);
        result.push(...seasons[season]);
    });

    return result;
}

// 检查是否为媒体格式
function isMediaFormat(filename) {
    const mediaExtensions = ['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.3gp', '.ts', '.m2ts', '.rmvb', '.rm'];
    const ext = path.extname(filename).toLowerCase();
    return mediaExtensions.includes(ext);
}

// 从G-Box API获取流媒体
async function getStreamsFromGBox(alistInfo) {
    try {
        // 调用G-Box的播放列表API
        const url = `${ALIST_GBOX_URL}/vod/playlist`;
        const params = {
            site: alistInfo.siteId,
            path: decodeURIComponent(alistInfo.encodedPath)
        };

        console.log(`获取播放列表: ${url}`, params);

        const headers = {};
        if (ALIST_TOKEN) {
            headers['Authorization'] = ALIST_TOKEN;
        }

        const response = await axios.get(url, {
            params,
            headers,
            timeout: 10000
        });

        if (response.data && response.data.list) {
            return response.data.list.map(item => ({
                url: item.url,
                title: item.name || path.basename(item.url),
                quality: getQualityFromName(item.name || item.url),
                size: item.size ? formatFileSize(item.size) : undefined
            }));
        }

        return [];

    } catch (error) {
        console.error('获取播放列表失败:', error);
        return [];
    }
}

// 从文件名获取质量信息
function getQualityFromName(filename) {
    if (filename.includes('4K') || filename.includes('2160p')) return '4K';
    if (filename.includes('1080p')) return '1080p';
    if (filename.includes('720p')) return '720p';
    if (filename.includes('480p')) return '480p';
    return 'Unknown';
}

// 格式化文件大小
function formatFileSize(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

// 注意：已移除运行时容器检测逻辑，现在使用安装时配置的参数

// 注意：移除了未使用的猜测IMDB ID函数

// 豆瓣ID到IMDB ID转换功能
async function getImdbIdFromDouban(doubanId) {
    if (!doubanId || doubanId === '0') {
        return null;
    }

    try {
        const doubanUrl = `https://movie.douban.com/subject/${doubanId}`;
        console.log(`获取IMDB ID: ${doubanUrl}`);

        const response = await axios.get(doubanUrl, {
            timeout: 10000,
            headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
            }
        });

        const html = response.data;

        // 方法1: 直接正则匹配 IMDb: tt开头的ID
        const imdbMatch1 = html.match(/IMDb:\s*(tt\d+)/i);
        if (imdbMatch1) {
            console.log(`方法1成功提取IMDB ID: ${imdbMatch1[1]}`);
            return imdbMatch1[1];
        }

        // 方法2: 匹配 imdb.com 链接中的ID
        const imdbMatch2 = html.match(/imdb\.com\/title\/(tt\d+)/i);
        if (imdbMatch2) {
            console.log(`方法2成功提取IMDB ID: ${imdbMatch2[1]}`);
            return imdbMatch2[1];
        }

        // 方法3: 使用 JSDOM 解析HTML，查找包含IMDb的元素
        try {
            const dom = new JSDOM(html);
            const document = dom.window.document;

            // 查找所有包含 "IMDb" 文本的元素
            const elements = Array.from(document.querySelectorAll('*')).filter(el =>
                el.textContent && el.textContent.includes('IMDb')
            );

            for (const element of elements) {
                const text = element.textContent;
                const match = text.match(/tt\d+/);
                if (match) {
                    console.log(`方法3成功提取IMDB ID: ${match[0]}`);
                    return match[0];
                }
            }
        } catch (jsdomError) {
            console.log('JSDOM解析失败，跳过方法3');
        }

        console.log(`未能从豆瓣页面提取IMDB ID: ${doubanId}`);
        return null;

    } catch (error) {
        console.error(`获取IMDB ID失败 (豆瓣ID: ${doubanId}):`, error.message);
        return null;
    }
}

// 启动服务器
app.listen(PORT, () => {
    console.log(`AList G-Box Addon Enhanced 运行在端口 ${PORT}`);
    console.log(`Manifest URL: http://localhost:${PORT}/manifest.json`);
    console.log(`\n配置信息:`);
    console.log(`  - 容器类型: ${CONTAINER_TYPE}`);
    console.log(`  - AList URL: ${ALIST_URL}`);
    console.log(`  - 搜索 URL: ${SEARCH_URL}`);
    console.log(`  - 容器名称: ${CONTAINER_NAME || '未配置'}`);
    console.log(`  - Token: ${ALIST_TOKEN ? '已配置' : '❌ 未配置 (必需)'}`);

    // 检查 token 配置
    if (!ALIST_TOKEN || ALIST_TOKEN.trim() === '') {
        console.log(`\n${'\x1b[31m'}⚠️ 警告: AList Token 未配置，插件无法正常工作！${'\x1b[0m'}`);
        console.log(`请配置 AList Token:`);
        console.log(`  1. 访问配置页面: http://localhost:${PORT}/configure`);
        console.log(`  2. 或重新运行安装脚本`);
    }

    console.log(`\n搜索策略:`);
    if (CONTAINER_TYPE === 'gbox') {
        console.log(`  - G-Box容器模式: 调用内置搜索API (5678端口)`);
        console.log(`  - 支持完整豆瓣元数据和IMDB ID转换`);
    } else {
        console.log(`  - 普通AList模式: 调用标准搜索API (/api/fs/search)`);
        console.log(`  - 使用固定海报图和文件路径显示`);
    }

    console.log(`\n功能特性:`);
    console.log(`  - 豆瓣ID到IMDB ID自动转换`);
    console.log(`  - 智能容器类型检测和配置`);
    console.log(`  - 电影和剧集的不同播放格式支持`);
    console.log(`  - 剧集按季集分组显示`);
    console.log(`  - 支持目录浏览和直接播放`);

    console.log(`\n使用说明:`);
    console.log(`  - 在Stremio中搜索关键词或浏览分类`);
    console.log(`  - 点击海报进入详情页或直接播放`);
    console.log(`  - 支持中文搜索和多种视频格式`);
});
