# Crystal: Economy


# This crystal contains the featues of Cobalt's economy system.
module Bot::Economy
  extend Discordrb::Commands::CommandContainer
  extend Discordrb::EventContainer
  include Bot::Models

  extend Convenience
  include Constants

  # Path to this crystal's data folder
  ECON_DATA_PATH = "#{ENV['DATA_PATH']}/economy"
  # Color role names and IDs
  COLOR_ROLES = {
      'Ghastly Green'     => 308634210564964353,
      'Obsolete Orange'   => 434036486808272916,
      'Breathtaking Blue' => 434036732162211861,
      'Lullaby Lavender'  => 434037025663090688,
      'Retro Red'         => 434040026192543764,
      'Whitey White'      => 436566003896418307,
      'Shallow Yellow'    => 440174617697583105,
      'Marvelous Magenta' => 440182036800471041
  }.freeze
  # Color role short names and IDs
  COLOR_ROLES_SHORT = {
      'green'    => 308634210564964353,
      'orange'   => 434036486808272916,
      'blue'     => 434036732162211861,
      'lavender' => 434037025663090688,
      'red'      => 434040026192543764,
      'white'    => 436566003896418307,
      'yellow'   => 440174617697583105,
      'magenta'  => 440182036800471041
  }.freeze
  # Mee6 override role names and IDs
  OVERRIDE_ROLES = {
      'Citizen Override'    => 460505017120587796,
      'Squire Override'     => 460505130203217921,
      'Knight Override'     => 460505230128185365,
      'Noble Override'      => 553321038478573569,
      'Monarch Override'    => 481049629773922304,
      'Wandbearer Override' => 553319697420910632
  }.freeze
  # Mee6 override role short names and IDs
  OVERRIDE_ROLES_SHORT = {
      'citizen'    => 460505017120587796,
      'squire'     => 460505130203217921,
      'knight'     => 460505230128185365,
      'noble'      => 553321038478573569,
      'monarch'    => 481049629773922304,
      'wandbearer' => 553319697420910632
  }.freeze
  # Mee6 role IDs
  MEE6_ROLES = {
      citizen:    320438721923252225,
      squire:     347071589768101908,
      knight:     321206686872502274,
      noble:      553320915409305609,
      monarch:    481049629773922304,
      wandbearer: 318519367971241984
  }.freeze
  # Mee6 role short names and IDs
  MEE6_ROLES_SHORT = {
      'citizen'    => 320438721923252225,
      'squire'     => 347071589768101908,
      'knight'     => 321206686872502274,
      'noble'      => 553320915409305609,
      'monarch'    => 481049629773922304,
      'wandbearer' => 318519367971241984
  }.freeze
  # #bot_commands ID
  BOT_COMMANDS_ID = 307726225458331649
  # #moderation_channel ID
  MODERATION_CHANNEL_ID = 330586271116165120
  # Time interval in seconds between checkins (23 hours)
  CHECKIN_INTERVAL = 82800
  # Time interval in seconds between payments for color roles (24 hours)
  COLOR_ROLE_DAILY_INTERVAL = 86400
  # Bucket for rate limiting money earning through chat activity (once every two minutes)
  EARN_BUCKET = Bot::BOT.bucket(
      :earn,
      limit:     1,
      time_span: 120
  )
  # Bucket for rate limiting money transfers (once every minute)
  TRANSFER_BUCKET = Bot::BOT.bucket(
      :transfer,
      limit:     1,
      time_span: 60
  )
  # Raffle reminder role ID
  RAFFLE_REMINDER_ID = 459714534425362434

  multiplier = 1

  # Give user Starbucks for every message they send, with a 2 minute delay between earning money this way
  message do |event|
    # Skip if event channel is disabled from message activity earning
    next if YAML.load_data!("#{ECON_DATA_PATH}/earn_disabled_channels.yml").include? event.channel.id

    # Skip is user is currently rate limited (has already earned money within the past 2 minutes)
    next if EARN_BUCKET.rate_limited? event.user.id

    economy_user = EconomyUser[event.user.id] || EconomyUser.create(id: event.user.id)

    # Add Starbucks to user and saves to database
    economy_user.money += (rand(1..5) * multiplier)
    economy_user.save
  end

  # Check user's economy profile
  command :profile, channels: [BOT_COMMANDS_ID, MODERATION_CHANNEL_ID] do |event, *args|
    # Set argument default to event user
    args[0] ||= event.user.id

    # Break unless given user is valid
    break unless (user = SERVER.get_user(args.join(' ')))

    economy_user = EconomyUser[user.id] || EconomyUser.create(id: user.id)
    to_next_checkin = if economy_user.next_checkin && economy_user.next_checkin > Time.now
                        (economy_user.next_checkin - Time.now).round.to_dhms
                      else 'None'
                      end

    # Respond with embed
    event.channel.send_embed do |embed|
      embed.author = {
          name:     "#{user.display_name} (#{user.distinct})",
          icon_url: user.avatar_url
      }
      embed.description = <<~DESC.strip
        **Balance:** #{pl(economy_user.money, 'Starbuck')}
        **Time until next check-in:** #{to_next_checkin}
      DESC
      embed.add_field(
          name:  'Color Role',
          value: economy_user.color_role
      )
      embed.color = 0xFFD700
      embed.footer = {text: 'Use +checkin once every 23 hours to earn 50 Starbucks.'}
    end
  end

  # Check in and get daily Starbucks
  command :checkin, channels: [BOT_COMMANDS_ID] do |event|
    economy_user = EconomyUser[event.user.id] || EconomyUser.create(id: event.user.id)

    # If user's next checkin time exists and has not passed, respond to user
    if economy_user.next_checkin && economy_user.next_checkin > Time.now
      time_to_next_checkin = (economy_user.next_checkin - Time.now).round.to_dhms
      event << "**#{event.user.mention}, you can't check in yet!** Time until next check-in: #{time_to_next_checkin}"

    # Otherwise:
    else
      # Add Starbucks based on user's highest Mewman role
      earned_money = if event.user.role? MEE6_ROLES[:wandbearer]
                       200
                     elsif event.user.role? MEE6_ROLES[:monarch]
                       175
                     elsif event.user.role? MEE6_ROLES[:noble]
                       150
                     elsif event.user.role? MEE6_ROLES[:knight]
                       125
                     elsif event.user.role? MEE6_ROLES[:squire]
                       100
                     elsif event.user.role? MEE6_ROLES[:citizen]
                       75
                     else 50
                     end
      earned_money *= multiplier
      economy_user.money += earned_money

      # Set next checkin time
      economy_user.next_checkin = Time.now + CHECKIN_INTERVAL

      # Save to database
      economy_user.save

      # Respond to user
      event.respond(
          <<~RESPONSE.strip,
            **#{event.user.mention}, you have checked in! You receive #{earned_money} Starbucks.**
            Check in again in 23 hours.
          RESPONSE
          false,
          {image: {url: 'http://i65.tinypic.com/2rc5379.gif'}}
      )
    end
  end

  command :multiplier do |event, arg|
    # Break unless user is moderator
    break unless event.user.role? MODERATOR_ID

    # If argument is given and greater than or equal to 0, set earn multiplier to argument
    if arg && arg.to_i >= 0
      multiplier = arg.to_i
      event << "**Set earn multiplier to #{multiplier}x.**"

    # Otherwise, return current multiplier
    else event << "**The current earn multiplier is #{multiplier}x.**"
    end
  end

  # Rent a color role
  command :rentarole, channels: [BOT_COMMANDS_ID, MODERATION_CHANNEL_ID] do |event, arg|
    # If argument is given:
    if arg
      # Break unless the given argument is one of the color roles
      break unless (role_id = COLOR_ROLES_SHORT[arg.downcase])

      role_name = COLOR_ROLES.key(role_id)
      economy_user = EconomyUser[event.user.id] || EconomyUser.create(id: event.user.id)

      # If user has enough money to rent a role:
      if economy_user.money >= 300
        # Deduct upfront cost of 300 Starbucks from user
        economy_user.money -= 300

        # Remove existing color and override roles
        event.user.remove_role(COLOR_ROLES.values + OVERRIDE_ROLES.values)

        # Add role to user
        event.user.add_role role_id

        # Set user's color role info
        economy_user.color_role = role_name
        economy_user.color_role_daily = Time.now + COLOR_ROLE_DAILY_INTERVAL

        # Save to database
        economy_user.save

        # Respond to user
        event << <<~RESPONSE.strip
          **#{event.user.mention}, you are now renting #{role_name}.**
          Enjoy your new color!
        RESPONSE

      # If user does not have enough money to rent a role, respond to user
      else event.send_temp("#{event.user.mention}, you don't have enough money to rent a color role!", 5)
      end

    # If no argument is given, respond to user with information embed
    else
      event.send_embed do |embed|
        embed.author = {
            name:     'Rent-A-Role: Info',
            icon_url: 'http://i68.tinypic.com/2rdkuwi.jpg'
        }
        embed.description = <<~DESC.strip
          This is the Rent-A-Role info page. You can rent one of the available color roles here at a time.
          Renting a role costs 300 starbucks upfront and costs 200 Starbucks a day to keep -- but it gives you a color and that's cool.
          The roles currently available are: #{COLOR_ROLES_SHORT.keys.map(&:capitalize).join(', ')}
          To rent a role, use this command again with the color name (i.e. `+rentarole yellow`).
          Use the command `+unrentarole` if you would like to give up your role -- you will be returned 100 Starbucks.
          However, be warned! If you are unable to pay the fee on any day, you will lose the role and will not be returned anything.
          While you only need 300 Starbucks to make the initial payment on a role, it is recommended you have an excess of money before making the payment.
        DESC
        embed.color = 0xFFD700
        embed.footer = {text: 'Use +checkin once every 23 hours to earn Starbucks.'}
      end
    end
  end

  # Purchase an override role
  command :getoverride, channels: [BOT_COMMANDS_ID, MODERATION_CHANNEL_ID] do |event, arg|
    # If argument is given:
    if arg
      # Break unless the given argument is one of the override roles
      break unless (role_id = OVERRIDE_ROLES_SHORT[arg.downcase])

      # Break unless user has the respective Mewman role of the override they are attempting to purchase
      break unless event.user.role? MEE6_ROLES_SHORT[arg.downcase]

      role_name = OVERRIDE_ROLES.key(role_id)
      economy_user = EconomyUser[event.user.id] || EconomyUser.create(id: event.user.id)

      # If user has enough money to purchase a role:
      if economy_user.money >= 200
        # Deduct cost of 200 Starbucks from user
        economy_user.money -= 200

        # Remove existing color and override roles
        event.user.remove_role(COLOR_ROLES.values + OVERRIDE_ROLES.values)

        # Adds role to user
        event.user.add_role role_id

        # Set user's color role info
        economy_user.color_role = role_name

        # Save to database
        economy_user.save

        # Respond to user
        event << <<~RESPONSE.strip
          **#{event.user.mention}, you now have the #{role_name}.**
          Enjoy your new color!
        RESPONSE

      # If user does not have enough money to purchase a role, respond to user
      else event.send_temp("#{event.user.mention}, you don't have enough money to purchase an override role!", 5)
      end

    # If no argument is given, respond to user with information embed
    else
      event.send_embed do |embed|
        embed.author = {
            name:     'Override Roles: Info',
            icon_url: 'http://i68.tinypic.com/2rdkuwi.jpg'
        }
        embed.description = <<~DESC.strip
          This is the override role info page. You can rent one of the available override roles here at a time.
          Override roles let you override your current color with a Mewman role color for 200 Starbucks.
          However, you must have the the override's respective Mewman role! (i.e. Mewman Noble for Noble override)
          The roles currently available are: #{OVERRIDE_ROLES_SHORT.keys.map(&:capitalize).join(', ')}
          To purchase an override role, use this command again with the color name (i.e. `+getoverride noble`).
          Use the command `+returnoverride` if you would like to give up your role.
        DESC
        embed.color = 0xFFD700
        embed.footer = {text: 'Use +checkin once every 23 hours to earn Starbucks.'}
      end
    end
  end

  # Return a color role
  command :unrentarole, channels: [BOT_COMMANDS_ID, MODERATION_CHANNEL_ID] do |event|
    economy_user = EconomyUser[event.user.id] || EconomyUser.create(id: event.user.id)

    # Breaks unless user is renting a color role
    break unless (role_id = COLOR_ROLES[economy_user.color_role])

    # Remove role from user
    event.user.remove_role role_id

    # Remove color role info
    economy_user.color_role = 'None'
    economy_user.color_role_daily = nil

    # Add 100 Starbucks to user
    economy_user.money += 100

    # Save to database
    economy_user.save

    # Respond to user
    event << <<~RESPONSE.strip
      **#{event.user.mention}, you have returned your role.**
      100 Starbucks have been refunded to your account.
    RESPONSE
  end

  # 30m cron job to verify users are paying for their color roles
  SCHEDULER.cron '*/30 * * * *' do
    # Iterate through users who are renting a role
    EconomyUser.all.select { |eu| eu.color_role_daily }.each do |economy_user|
      # Skip unless the time for the daily payment has passed
      next unless economy_user.color_role_daily && Time.now > economy_user.color_role_daily

      # If user has enough money to pay the daily cost:
      if economy_user.money >= 200
        # Deduct daily cost of 200 Starbucks from user
        economy_user.money -= 200

        # Set next daily payment time
        economy_user.color_role_daily += COLOR_ROLE_DAILY_INTERVAL

        # Save to database
        economy_user.save

      # If user does not have enough money to pay the daily cost, remove role, update database and DM user
      else
        event.user.remove_role(COLOR_ROLES[economy_user.color_role])

        economy_user.color_role = 'None'
        economy_user.color_role_daily = nil
        economy_user.save

        event.user.dm <<~DM.strip
          **Due to insufficient funds for today's payment, your role has been returned.**
          No money has been deducted from your account for today's payment.
        DM
      end
    end
  end

  # Add, edit, remove or call a tag
  command :tag, channels: [BOT_COMMANDS_ID, MODERATION_CHANNEL_ID] do |event, *args|
    # Break unless arguments are given
    break unless args.any?

    # Cases first argument
    case args[0].downcase
    when 'add'
      # Break unless tag key is given
      break unless args.size >= 2

      # If user has enough money to purchase a tag:
      if (economy_user = EconomyUser[event.user.id] || EconomyUser.create(id: event.user.id)).money >= 30
        # If tag already exists, respond to user
        if Tag[key: (key = args[1..-1].join(' '))]
          event.send_temp('That tag already exists!', 5)

        # Otherwise:
        else
          tag = Tag.create(key: key, user: event.user.id)

          # Deduct 30 Starbucks from user
          economy_user.money -= 30

          # Prompt user for tag content and await response
          prompt = event.respond <<~RESPONSE.strip
            **Registered the tag "#{key}" to you for 30 Starbucks, #{event.user.mention}!**
            Reply with what you would like it to say.
          RESPONSE
          response = prompt.await!

          # Set tag content and save to database
          tag.content = response.message.content
          tag.save

          # Delete prompt and response
          prompt.delete
          response.delete

          # Respond to user
          event << '**The tag has been added.**'
        end

      # If user does not have enough money, respond to user
      else event.send_temp("#{event.user.mention}, you don't have enough money to purchase a tag!", 5)
      end

    when 'edit'
      # Break unless tag key is given
      break unless args.size >= 2

      # If tag with given key exists:
      if (tag = Tag[key: args[1..-1].join(' ')])
        # If tag belongs to event user:
        if tag.user == event.user.id
          # Prompt user for tag content and await response
          prompt = event.respond <<~RESPONSE.strip
            **Now editing your tag "#{tag.key}", #{event.user.mention}!**
            Reply with what you would like it to say.
          RESPONSE
          response = prompt.await!

          # Set new tag content and save to database
          tag.content = response.message.content
          tag.save

          # Delete prompt and response
          prompt.delete
          response.delete

          # Respond to user
          event << '**The tag has been edited.**'

        # If tag does not belong to event user, respond to user
        else event.send_temp("#{event.user.mention}, that tag doesn't belong to you!", 5)
        end

      # If no tag with given key exists, respond to user
      else event.send_temp("That tag doesn't exist!", 5)
      end

    when 'delete', 'remove'
      # Break unless tag key is given
      break unless args.size >= 2

      # If tag with given key exists:
      if (tag = Tag[key: args[1..-1].join(' ')])
        # If tag belongs to event user or user is moderator, delete tag and respond to user
        if tag.user == event.user.id ||
           event.user.role?(MODERATOR_ID)
          tag.destroy
          event << '**The tag has been deleted.**'

        # Otherwise, respond to user
        else event.send_temp("#{event.user.mention}, that tag doesn't belong to you!", 5)
        end

      # If no tag with given key exists, respond to user
      else event.send_temp("That tag doesn't exist!", 5)
      end

    else
      # Break unless tag with given key exists
      break unless (tag = Tag[key: args.join('')])

      # Respond with tag content
      event << tag.content
    end
  end

  # Add, edit or remove a custom command
  command :mycom, channels: [BOT_COMMANDS_ID, MODERATION_CHANNEL_ID] do |event, arg1, arg2|
    # Break unless at least the first argument is given
    break unless arg1

    # Cases first argument
    case arg1.downcase
    when 'set'
      # Break unless command name is given
      break unless arg2

      # If user has enough money to purchase a tag:
      if (economy_user = EconomyUser[event.user.id] || EconomyUser.create(id: event.user.id)).money >= 15000
        # If command already exists, respond to user
        if CustomCommand[name: (name = arg2.downcase)]
          event.send_temp('A custom command with that name already exists!', 5)

        # Otherwise:
        else
          command = CustomCommand.create(name: name, user: event.user.id)

          # Deduct 15000 Starbucks from user
          economy_user.money -= 15000

          # Prompt user for command content and await response
          prompt = event.respond <<~RESPONSE.strip
            **Registered the command +#{name} to you for 15000 Starbucks, #{event.user.mention}!**
            Reply with what you would like it to say.
          RESPONSE
          response = prompt.await!

          # Set command content and save to database
          command.content = response.message.content
          command.save

          # Delete prompt and response
          prompt.delete
          response.delete

          # Respond to user
          event << '**The command has been set.**'
        end

        # If user does not have enough money, respond to user
      else event.send_temp("#{event.user.mention}, you don't have enough money to purchase a custom command!", 5)
      end

    when 'edit'
      # Break unless user has a custom command
      break unless (command = CustomCommand[user: event.user.id])

      # Prompt user for tag content and await response
      prompt = event.respond <<~RESPONSE.strip
        **Now editing your command +"#{command.name}", #{event.user.mention}!**
        Reply with what you would like it to say.
      RESPONSE
      response = prompt.await!

      # Set new tag content and save to database
      command.content = response.message.content
      command.save

      # Delete prompt and response
      prompt.delete
      response.delete

      # Respond to user
      event << '**The command has been edited.**'

    when 'delete', 'remove'
      # If user is a moderator and command name has been given:
      if event.user.role?(MODERATOR_ID) &&
         arg2
        # If a custom command with the given name exists, delete it and respond to user
        if (command = CustomCommand[name: arg2.downcase])
          command.destroy
          event << '**The command has been deleted.**'

        # Otherwise, respond to user
        else event.send_temp("That command doesn't exist!", 5)
        end

      # If user has a custom command, delete it and respond to user
      elsif (command = CustomCommand[user: event.user.id])
        command.destroy
        event << '**The command has been deleted.**'
      end
    end
  end

  # Respond to user when they are using their custom command
  message start_with: '+' do |event|
    # Skip unless a custom command with the given name exists
    next unless (command = CustomCommand[name: event.message.content[1..-1]])

    # Skip unless the one calling the command is the command's owner
    next unless command.user == event.user.id

    # Respond to user
    event << command.content
  end

  # Display richest users
  command :richest, channels: [BOT_COMMANDS_ID, MODERATION_CHANNEL_ID] do |event|
    sorted_economy_users = EconomyUser.order(:money).reverse.all
    sorted_economy_users.select! { |eu| Bot::BOT.user(eu.id) }
    richest = sorted_economy_users[0..9]

    # Respond with embed containing leaderboard
    event.send_embed do |embed|
      embed.author = {
          name:     'Bank: Top 10',
          icon_url: 'http://i68.tinypic.com/2rdkuwi.jpg'
      }
      embed.description = richest.each_with_index.map do |economy_user, index|
        "• **#{index + 1} - #{Bot::BOT.user(economy_user.id).distinct}** #{economy_user.money} Starbucks"
      end.join("\n")
      embed.color = 0xFFD700
    end
  end

  # Display raffle info, purchase ticket(s) or toggle raffle reminder role
  command :raffle, channels: [BOT_COMMANDS_ID, MODERATION_CHANNEL_ID] do |event, arg1 = 'check', arg2 = '1'|
    raffle = Raffle.get

    # Case first argument
    case arg1.downcase
    when 'check', 'info'
      # Respond with embed containing raffle info
      event.send_embed do |embed|
        embed.author = {
            name:     'Raffle: Info',
            icon_url: 'http://i68.tinypic.com/2rdkuwi.jpg'
        }
        embed.description = <<~DESC.strip
          **Current prize:** #{raffle.pool} Starbucks
          **Time until winner draw:** #{(raffle.end_time - Time.now).round.to_dhms}
          **Your tickets:** #{raffle.tickets.count { |t| t.user == event.user.id }}

          **Use the command `+raffle buyticket [number]` (default 1) to purchase raffle tickets.**
          Tickets cost 100 Starbucks each.
        DESC
        embed.color = 0xFFD700
        embed.footer = {text: 'Use `+raffle reminder` to be pinged every time a new raffle starts.'}
      end

    when 'buyticket'
      # Break unless the number of tickets to buy is greater than 0
      break unless (tickets = arg2.to_i > 0)

      economy_user = EconomyUser[event.user.id] || EconomyUser.create(id: event.user.id)

      # Break unless user has enough money to purchase given number of tickets
      break unless economy_user.money > 100 * tickets

      # Iterate the given number of times and deduct ticket cost from user, create ticket, add ticket to
      # raffle and add to prize pool
      tickets.times do
        economy_user.money -= 100
        ticket = RaffleTicket.create(id: event.user.id)
        raffle.add_raffle_ticket(ticket)
        raffle.pool += 80
      end

      # Save to database
      raffle.save

      # Respond to user
      event << <<~RESPONSE.strip
        **#{event.user.mention}, you have purchased #{pl(ticket, 'ticket')} for #{tickets * 100} Starbucks.**
        The current prize pool is #{raffle.pool} Starbucks.
      RESPONSE

    when 'reminder'
      # If user has reminder role, remove it and respond to user
      if event.user.role? RAFFLE_REMINDER_ID
        event.user.remove_role RAFFLE_REMINDER_ID
        event.send_temp("#{event.user.mention}, you will no longer be pinged when a new raffle starts.", 5)

      # Otherwise, add role and respond to user
      else
        event.user.add_role RAFFLE_REMINDER_ID
        event.send_temp("#{event.user.mention}, you will now be pinged when a new raffle starts.", 5)
      end
    end
  end
end