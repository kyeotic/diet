import urlJoin from 'url-join'

import { request } from '../http/client'
import config from '../config.js'

const api = (...parts) => urlJoin(config.apiHost, 'v1', ...parts)

export const getDietLogs = async () => {
  let items = await request(api('dietlogs'))
  return items.map(fromApi)
}

function fromApi(item) {
  return {
    ...item,
    // The server time is UTC, we want to sidestep timezone issues
    date: new Date(item.date.replace(/-/g, '/').replace(/T.+/, ''))
  }
}
